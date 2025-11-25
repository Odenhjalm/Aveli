import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

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
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.dumpErrorToConsole(details);
        if (!kReleaseMode) {
          debugPrint('FlutterError: ${details.exceptionAsString()}');
          debugPrint(details.stack?.toString() ?? 'No stack trace');
        }
      };
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        if (!kReleaseMode) {
          debugPrint('Uncaught platform error: $error');
          debugPrint(stackTrace.toString());
        }
        return false;
      };

      MediaKit.ensureInitialized();
      try {
        await dotenv.load(fileName: '.env');
      } catch (_) {
        // Filen är valfri; saknas den så förlitar vi oss på --dart-define eller runtime vars.
      }
      final rawBaseUrl =
          dotenv.maybeGet('API_BASE_URL') ??
          const String.fromEnvironment('API_BASE_URL');
      final baseUrl = _resolveApiBaseUrl(rawBaseUrl);
      final publishableKey =
          dotenv.maybeGet('STRIPE_PUBLISHABLE_KEY') ??
          const String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
      final merchantDisplayName =
          dotenv.maybeGet('STRIPE_MERCHANT_DISPLAY_NAME') ??
          const String.fromEnvironment('STRIPE_MERCHANT_DISPLAY_NAME');
      final subscriptionsEnabledRaw =
          dotenv.maybeGet('SUBSCRIPTIONS_ENABLED') ??
          const String.fromEnvironment(
            'SUBSCRIPTIONS_ENABLED',
            defaultValue: 'false',
          );
      final subscriptionsEnabled =
          subscriptionsEnabledRaw.toLowerCase() == 'true';

      final supabaseUrl = EnvResolver.supabaseUrl;
      final supabaseAnonKey = EnvResolver.supabaseAnonKey;

      final imageLoggingRaw =
          dotenv.maybeGet('IMAGE_LOGGING') ??
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
      if (!kReleaseMode) {
        debugPrint('Zoned error: $error');
        debugPrint(stackTrace.toString());
      }
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
  if (Platform.isAndroid && loopbackHosts.contains(parsed.host)) {
    return parsed.replace(host: '10.0.2.2').toString();
  }
  if (Platform.isIOS && parsed.host == '0.0.0.0') {
    return parsed.replace(host: '127.0.0.1').toString();
  }
  return url;
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
