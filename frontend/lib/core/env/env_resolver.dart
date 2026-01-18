import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

const _apiBaseUrlDefine =
    String.fromEnvironment('API_BASE_URL', defaultValue: '');
const _frontendUrlDefine =
    String.fromEnvironment('FRONTEND_URL', defaultValue: '');
const _oauthRedirectWebDefine =
    String.fromEnvironment('OAUTH_REDIRECT_WEB', defaultValue: '');
const _oauthRedirectMobileDefine =
    String.fromEnvironment('OAUTH_REDIRECT_MOBILE', defaultValue: '');
const _supabaseUrlDefine =
    String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const _supabasePublishableApiKeyDefine =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_API_KEY', defaultValue: '');
const _supabasePublicApiKeyDefine =
    String.fromEnvironment('SUPABASE_PUBLIC_API_KEY', defaultValue: '');
const _stripePublishableKeyDefine =
    String.fromEnvironment('STRIPE_PUBLISHABLE_KEY', defaultValue: '');
const _stripeMerchantDisplayNameDefine =
    String.fromEnvironment('STRIPE_MERCHANT_DISPLAY_NAME', defaultValue: '');
const _subscriptionsEnabledDefine =
    String.fromEnvironment('SUBSCRIPTIONS_ENABLED', defaultValue: '');
const _imageLoggingDefine =
    String.fromEnvironment('IMAGE_LOGGING', defaultValue: '');

class EnvResolver {
  static bool get _canReadDotenv =>
      dotenv.isInitialized && (!kIsWeb || kDebugMode);

  static String _resolveWithDefine({
    required String envKey,
    required String defineValue,
  }) {
    final normalizedDefine = defineValue.trim();
    if (normalizedDefine.isNotEmpty) return normalizedDefine;
    if (!_canReadDotenv) return '';
    return _readEnv(envKey);
  }

  static String _readEnv(String key) {
    if (!_canReadDotenv) return '';
    final value = dotenv.maybeGet(key);
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
    return '';
  }

  static String _readEnvFirst(Iterable<String> keys) {
    for (final key in keys) {
      final value = _readEnv(key);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String get frontendUrl => _resolveWithDefine(
        envKey: 'FRONTEND_URL',
        defineValue: _frontendUrlDefine,
      );

  static String get supabaseUrl => _resolveWithDefine(
        envKey: 'SUPABASE_URL',
        defineValue: _supabaseUrlDefine,
      );

  static String get supabasePublishableKey {
    final publishable = _resolveWithDefine(
      envKey: 'SUPABASE_PUBLISHABLE_API_KEY',
      defineValue: _supabasePublishableApiKeyDefine,
    );
    if (publishable.isNotEmpty) return publishable;
    final publicDefine = _supabasePublicApiKeyDefine.trim();
    if (publicDefine.isNotEmpty) return publicDefine;
    return _readEnvFirst(const [
      'SUPABASE_PUBLISHABLE_API_KEY',
      'SUPABASE_PUBLIC_API_KEY',
    ]);
  }

  static String get apiBaseUrl => _resolveWithDefine(
        envKey: 'API_BASE_URL',
        defineValue: _apiBaseUrlDefine,
      );

  static String get oauthRedirectWeb => _resolveWithDefine(
        envKey: 'OAUTH_REDIRECT_WEB',
        defineValue: _oauthRedirectWebDefine,
      );

  static String get oauthRedirectMobile => _resolveWithDefine(
        envKey: 'OAUTH_REDIRECT_MOBILE',
        defineValue: _oauthRedirectMobileDefine,
      );

  static String get stripePublishableKey => _resolveWithDefine(
        envKey: 'STRIPE_PUBLISHABLE_KEY',
        defineValue: _stripePublishableKeyDefine,
      );

  static String get stripeMerchantDisplayName => _resolveWithDefine(
        envKey: 'STRIPE_MERCHANT_DISPLAY_NAME',
        defineValue: _stripeMerchantDisplayNameDefine,
      );

  static bool get subscriptionsEnabled {
    final defined = _subscriptionsEnabledDefine.trim();
    if (defined.isNotEmpty) return defined.toLowerCase() == 'true';
    final raw = _readEnv('SUBSCRIPTIONS_ENABLED');
    return (raw.isEmpty ? 'false' : raw).toLowerCase() == 'true';
  }

  static bool get imageLoggingEnabled {
    final defined = _imageLoggingDefine.trim();
    if (defined.isNotEmpty) return defined.toLowerCase() != 'false';
    final raw = _readEnv('IMAGE_LOGGING');
    return (raw.isEmpty ? 'true' : raw).toLowerCase() != 'false';
  }

  static void debugLogResolved() {
    if (!kDebugMode) return;
    debugPrint(
      'EnvResolver resolved: '
      'apiBaseUrl=${_logValue(apiBaseUrl)} '
      'frontendUrl=${_logValue(frontendUrl)} '
      'oauthRedirectWeb=${_logValue(oauthRedirectWeb)} '
      'oauthRedirectMobile=${_logValue(oauthRedirectMobile)} '
      'supabaseUrl=${_logValue(supabaseUrl)} '
      'stripeKey=${_logValue(stripePublishableKey)} '
      'source=${(_canReadDotenv) ? 'dart-define>dotenv' : 'dart-define-only'}',
    );
  }

  static String _logValue(String value) => value.isEmpty ? '(empty)' : value;
}
