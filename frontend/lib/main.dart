import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter/foundation.dart';

import 'package:media_kit/media_kit.dart';
import 'package:wisdom/core/env/app_config.dart';
import 'package:wisdom/core/env/env_resolver.dart';
import 'package:wisdom/core/env/env_state.dart';
import 'package:wisdom/shared/utils/image_error_logger.dart';

import 'shared/theme/light_theme.dart';
import 'shared/widgets/background_layer.dart';
import 'core/routing/app_router.dart';
import 'shared/theme/controls.dart';
import 'package:wisdom/core/auth/auth_http_observer.dart';
import 'package:wisdom/core/auth/auth_controller.dart' hide AuthState;
import 'package:wisdom/features/paywall/application/entitlements_notifier.dart';
import 'package:wisdom/core/routing/app_routes.dart';
import 'package:wisdom/core/routing/route_paths.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _logBootstrapError(
      'FlutterError',
      details.exception,
      details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    _logBootstrapError('PlatformDispatcher', error, stackTrace);
    return true;
  };

  runZonedGuarded(
    () async {
      if (kIsWeb) {
        debugPrint('Skipping MediaKit.ensureInitialized() on web.');
      } else {
        await MediaKit.ensureInitialized();
      }
      await _ensureDotEnvInitialized();
      final env = dotenv.isInitialized
          ? Map<String, String>.from(dotenv.env)
          : const <String, String>{};

      EnvResolver.seedFrom(env);

      final rawBaseUrl =
          env['API_BASE_URL'] ?? const String.fromEnvironment('API_BASE_URL');
      final baseUrl = _resolveApiBaseUrl(rawBaseUrl);
      final publishableKey = env['STRIPE_PUBLISHABLE_KEY'] ??
          const String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
      final merchantDisplayName =
          env['STRIPE_MERCHANT_DISPLAY_NAME'] ??
          const String.fromEnvironment('STRIPE_MERCHANT_DISPLAY_NAME');
      final subscriptionsEnabledRaw =
          env['SUBSCRIPTIONS_ENABLED'] ??
          const String.fromEnvironment(
            'SUBSCRIPTIONS_ENABLED',
            defaultValue: 'false',
          );
      final subscriptionsEnabled =
          subscriptionsEnabledRaw.toLowerCase() == 'true';

      final supabaseUrl = EnvResolver.supabaseUrl;
      final supabaseAnonKey = EnvResolver.supabaseAnonKey;

      final imageLoggingRaw = env['IMAGE_LOGGING'] ??
          const String.fromEnvironment('IMAGE_LOGGING', defaultValue: 'true');
      final imageLoggingEnabled = imageLoggingRaw.toLowerCase() != 'false';

      final missingKeys = <String>[];
      if (rawBaseUrl.isEmpty) {
        missingKeys.add('API_BASE_URL');
      }
      if (publishableKey.isEmpty) {
        missingKeys.add('STRIPE_PUBLISHABLE_KEY');
      }
      if (merchantDisplayName.isEmpty) {
        missingKeys.add('STRIPE_MERCHANT_DISPLAY_NAME');
      }
      if (supabaseUrl.isEmpty) {
        missingKeys.add('SUPABASE_URL');
      }
      if (supabaseAnonKey.isEmpty) {
        missingKeys.add('SUPABASE_ANON_KEY');
      }

      if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
        await supa.Supabase.initialize(
          url: EnvResolver.supabaseUrl,
          anonKey: EnvResolver.supabaseAnonKey,
          authOptions: const supa.FlutterAuthClientOptions(
            authFlowType: supa.AuthFlowType.pkce,
          ),
        );
      } else {
        debugPrint(
          'Supabase config saknas. Checkout/token-flöden kan kräva SUPABASE_URL och SUPABASE_ANON_KEY.',
        );
      }

      final stripeSupportedPlatforms = {
        TargetPlatform.android,
        TargetPlatform.iOS,
      };
      final supportsNativeStripe = stripeSupportedPlatforms.contains(
        defaultTargetPlatform,
      );
      final canInitStripe =
          publishableKey.isNotEmpty && !kIsWeb && supportsNativeStripe;

      if (canInitStripe) {
        Stripe.publishableKey = publishableKey;
        Stripe.merchantIdentifier = merchantDisplayName.isNotEmpty
            ? merchantDisplayName
            : 'Aveli';
        await Stripe.instance.applySettings();
      }
      if (!canInitStripe && publishableKey.isNotEmpty) {
        debugPrint(
          kIsWeb
              ? 'Stripe initialisering hoppades över – flutter_stripe stöds inte på webbläsare ännu.'
              : 'Stripe initialisering hoppades över – plattform ${defaultTargetPlatform.name} stöds inte.',
        );
      }

      final envInfo = missingKeys.isEmpty
          ? envInfoOk
          : EnvInfo(status: EnvStatus.missing, missingKeys: missingKeys);

      // Warn in release builds if API_BASE_URL is not HTTPS.
      if (kReleaseMode && baseUrl.startsWith('http://')) {
        debugPrint(
          'WARNING: API_BASE_URL is using HTTP in release. Use HTTPS for production.',
        );
      }
      runApp(
        ProviderScope(
          overrides: [
            envInfoProvider.overrideWith((ref) => envInfo),
            appConfigProvider.overrideWithValue(
              AppConfig(
                apiBaseUrl: baseUrl,
                stripePublishableKey: publishableKey,
                stripeMerchantDisplayName: merchantDisplayName.isNotEmpty
                    ? merchantDisplayName
                    : 'Aveli',
                subscriptionsEnabled: subscriptionsEnabled,
                imageLoggingEnabled: imageLoggingEnabled,
              ),
            ),
          ],
          child: const WisdomApp(),
        ),
      );
    },
    (error, stackTrace) {
      _logBootstrapError('Uncaught zone error', error, stackTrace);
    },
  );
}

String _resolveApiBaseUrl(String url) {
  if (url.isEmpty) {
    return url;
  }
  final parsed = Uri.tryParse(url);
  if (parsed == null || parsed.host.isEmpty) {
    return url;
  }
  if (kIsWeb) {
    const loopbackHosts = {'0.0.0.0', '127.0.0.1'};
    if (loopbackHosts.contains(parsed.host)) {
      return parsed.replace(host: 'localhost').toString();
    }
    return url;
  }
  const loopbackHosts = {'localhost', '127.0.0.1', '0.0.0.0'};
  if (defaultTargetPlatform == TargetPlatform.android &&
      loopbackHosts.contains(parsed.host)) {
    return parsed.replace(host: '10.0.2.2').toString();
  }
  if (defaultTargetPlatform == TargetPlatform.iOS &&
      parsed.host == '0.0.0.0') {
    return parsed.replace(host: '127.0.0.1').toString();
  }
  return url;
}

void _logBootstrapError(String source, Object error, StackTrace? stackTrace) {
  debugPrint('$source: $error');
  if (stackTrace != null) {
    debugPrintStack(stackTrace: stackTrace);
  }
}

Future<void> _ensureDotEnvInitialized() async {
  if (dotenv.isInitialized) {
    return;
  }
  try {
    await dotenv.load(fileName: '.env');
    return;
  } catch (error, stackTrace) {
    debugPrint('dotenv load failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
  // Initialize with an empty map so maybeGet can be used safely on web builds
  // where the .env asset may not be present.
  dotenv.testLoad(fileInput: const {});
}

class WisdomApp extends ConsumerWidget {
  const WisdomApp({super.key});

  static final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sync image logging toggle from AppConfig.
    final cfg = ref.watch(appConfigProvider);
    ImageErrorLogger.enabled = cfg.imageLoggingEnabled;
    ref.listen<AsyncValue<AuthHttpEvent>>(authHttpEventsProvider, (
      previous,
      next,
    ) {
      final router = ref.read(appRouterProvider);
      next.whenData((event) {
        final messenger = _messengerKey.currentState;
        final message = switch (event) {
          AuthHttpEvent.sessionExpired =>
            'Sessionen har gått ut. Logga in igen.',
          AuthHttpEvent.forbidden =>
            'Du saknar behörighet för den här åtgärden.',
        };
        if (messenger != null) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        final locationUri = router.routeInformationProvider.value.uri;
        switch (event) {
          case AuthHttpEvent.sessionExpired:
            if (locationUri.path != RoutePath.login) {
              final redirectTarget = locationUri.toString().isEmpty
                  ? RoutePath.home
                  : locationUri.toString();
              router.goNamed(
                AppRoute.login,
                queryParameters: {'redirect': redirectTarget},
              );
            }
            break;
          case AuthHttpEvent.forbidden:
            const restricted = {
              RoutePath.admin,
              RoutePath.teacherHome,
              RoutePath.teacherEditor,
              RoutePath.studio,
            };
            if (restricted.contains(locationUri.path)) {
              router.goNamed(AppRoute.home);
            }
            break;
        }
      });
    });

    ref.listen(authControllerProvider, (prev, next) {
      final notifier = ref.read(entitlementsNotifierProvider.notifier);
      final wasAuthed = prev?.profile != null;
      final isAuthed = next.profile != null;
      if (isAuthed && !wasAuthed) {
        notifier.refresh();
      } else if (!isAuthed && wasAuthed) {
        notifier.reset();
      }
    });

    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Aveli',
      theme: buildLightTheme(),
      themeMode: ThemeMode.light,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('sv')],
      scaffoldMessengerKey: _messengerKey,
      routerConfig: router,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final themed = Theme(
          data: Theme.of(
            context,
          ).copyWith(radioTheme: cleanRadioTheme(context)),
          child: AppBackground(child: child),
        );
        return themed;
      },
    );
  }
}
