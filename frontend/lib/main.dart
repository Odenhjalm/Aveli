import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aveli/l10n/app_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

import 'package:media_kit/media_kit.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/env/env_resolver.dart';
import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/shared/utils/image_error_logger.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/auth/auth_controller.dart' hide AuthState;
import 'package:aveli/features/paywall/application/entitlements_notifier.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/core/deeplinks/deep_link_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'shared/theme/light_theme.dart';
import 'shared/widgets/background_layer.dart';
import 'core/routing/app_router.dart';
import 'shared/theme/controls.dart';
import 'shared/utils/l10n.dart';

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

      if (kIsWeb) {
        final base = Uri.base;
        final fragmentHasAuth =
            base.fragment.contains('access_token') ||
            base.fragment.contains('refresh_token') ||
            base.fragment.contains('code=') ||
            base.fragment.contains('token_type');
        if (fragmentHasAuth) {
          debugPrint(
            'OAuth fragment detected, preserving Uri.fragment for Supabase session parse.',
          );
        }
      }

      MediaKit.ensureInitialized();
      await _loadEnvFile(requiredFile: false);
      if (dotenv.isInitialized) {
        debugPrint('ENV KEYS: ${dotenv.env.keys}');
        debugPrint(
          'DOTENV STRIPE_PUBLISHABLE_KEY=${dotenv.maybeGet('STRIPE_PUBLISHABLE_KEY')}',
        );
        debugPrint(
          'DOTENV SUPABASE_PUBLISHABLE_API_KEY=${dotenv.maybeGet('SUPABASE_PUBLISHABLE_API_KEY')}',
        );
      } else {
        debugPrint(
          'Dotenv not initialized; using dart-define/runtime values only.',
        );
      }
      EnvResolver.debugLogResolved();

      final rawBaseUrl = EnvResolver.apiBaseUrl;
      final baseUrl = _resolveApiBaseUrl(rawBaseUrl);
      final publishableKey = EnvResolver.stripePublishableKey;
      final merchantDisplayName = EnvResolver.stripeMerchantDisplayName;
      final subscriptionsEnabled = EnvResolver.subscriptionsEnabled;

      final supabaseUrl = EnvResolver.supabaseUrl;
      final supabasePublishableKey = EnvResolver.supabasePublishableKey;
      final oauthRedirectWeb = EnvResolver.oauthRedirectWeb;
      final oauthRedirectMobile = EnvResolver.oauthRedirectMobile;

      final imageLoggingEnabled = EnvResolver.imageLoggingEnabled;

      if (kDebugMode) {
        debugPrint(
          'Env resolved apiBase=$baseUrl '
          'supabase=$supabaseUrl '
          'publishableKey=${supabasePublishableKey.isEmpty ? "(empty)" : "(provided)"} '
          'redirectWeb=$oauthRedirectWeb '
          'redirectMobile=$oauthRedirectMobile',
        );
      }

      final missingKeys = <String>[];
      if (rawBaseUrl.isEmpty) {
        missingKeys.add('API_BASE_URL');
      }
      if (publishableKey.isEmpty) {
        missingKeys.add('STRIPE_PUBLISHABLE_KEY');
      }
      if (supabaseUrl.isEmpty) {
        missingKeys.add('SUPABASE_URL');
      }
      if (supabasePublishableKey.isEmpty) {
        missingKeys.add('SUPABASE_PUBLISHABLE_API_KEY/SUPABASE_PUBLIC_API_KEY');
      }
      if (kIsWeb) {
        if (oauthRedirectWeb.isEmpty) {
          missingKeys.add('OAUTH_REDIRECT_WEB');
        }
      } else {
        if (oauthRedirectMobile.isEmpty) {
          missingKeys.add('OAUTH_REDIRECT_MOBILE');
        }
      }

      if (missingKeys.isNotEmpty) {
        debugPrint(
          'Missing required environment keys: ${missingKeys.join(', ')}. '
          '${kIsWeb ? 'Provide them via --dart-define for Flutter Web.' : 'Provide them via --dart-define or a local environment file.'}',
        );
      }

      if (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty) {
        await supa.Supabase.initialize(
          url: supabaseUrl,
          anonKey: supabasePublishableKey,
          authOptions: const supa.FlutterAuthClientOptions(
            authFlowType: supa.AuthFlowType.pkce,
          ),
        );
      } else {
        debugPrint(
          'Supabase config saknas. Checkout/token-flöden kan kräva SUPABASE_URL och SUPABASE_PUBLISHABLE_API_KEY.',
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
          child: const AveliApp(),
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

Future<void> _loadEnvFile({required bool requiredFile}) async {
  const fileName = String.fromEnvironment('DOTENV_FILE', defaultValue: '');
  if (kIsWeb) {
    if (!kDebugMode) {
      debugPrint('Skipping dotenv load on web (dart-define only).');
      return;
    }
    const fallbackWebFile = '.env.web';
    final webFile = fileName.isNotEmpty ? fileName : fallbackWebFile;
    try {
      await dotenv.load(fileName: webFile, isOptional: true);
      debugPrint('Loaded web dotenv from $webFile (debug).');
    } catch (error) {
      debugPrint('Warning: Could not load $webFile ($error)');
    }
    return;
  }
  if (fileName.isEmpty) {
    debugPrint(
      'No DOTENV_FILE provided; relying on runtime environment and dart-define.',
    );
    return;
  }
  try {
    await dotenv.load(fileName: fileName, isOptional: !requiredFile);
  } catch (error) {
    final message = 'Could not load $fileName ($error)';
    if (requiredFile) {
      throw StateError(message);
    }
    debugPrint('Warning: $message');
  }
}

class AveliApp extends ConsumerWidget {
  const AveliApp({super.key});

  static final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sync image logging toggle from AppConfig.
    final cfg = ref.watch(appConfigProvider);
    ImageErrorLogger.enabled = cfg.imageLoggingEnabled;
    final deepLinks = ref.watch(deepLinkServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      deepLinks.init();
    });
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
      onGenerateTitle: (context) => context.l10n.appTitle,
      theme: buildLightTheme(),
      themeMode: ThemeMode.light,
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: (locales, supported) {
        if (locales != null) {
          for (final locale in locales) {
            if (supported.contains(locale)) return locale;
            final languageMatch = supported.firstWhere(
              (supportedLocale) =>
                  supportedLocale.languageCode == locale.languageCode,
              orElse: () => const Locale('en'),
            );
            if (languageMatch.languageCode == locale.languageCode) {
              return languageMatch;
            }
          }
        }
        return const Locale('en');
      },
      scrollBehavior: const AveliScrollBehavior(),
      scaffoldMessengerKey: _messengerKey,
      routerConfig: router,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final path = router.routeInformationProvider.value.uri.path;
        final isBrandedSurface =
            path == RoutePath.landingRoot ||
            path == RoutePath.landing ||
            path == RoutePath.home ||
            path == RoutePath.privacy ||
            path == RoutePath.terms;
        final baseTheme = Theme.of(context);
        final themeData =
            (isBrandedSurface ? buildLightTheme(forLanding: true) : baseTheme)
                .copyWith(radioTheme: cleanRadioTheme(context));
        return Theme(
          data: themeData,
          child: AppBackground(child: child),
        );
      },
    );
  }
}

class AveliScrollBehavior extends MaterialScrollBehavior {
  const AveliScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final platform = getPlatform(context);
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.android) {
      return const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    return const ClampingScrollPhysics();
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
