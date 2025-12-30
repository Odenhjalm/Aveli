import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

const _apiBaseUrlDefine =
    String.fromEnvironment('API_BASE_URL', defaultValue: '');
const _frontendUrlDefine =
    String.fromEnvironment('FRONTEND_URL', defaultValue: '');
const _oauthRedirectWebDefine =
    String.fromEnvironment('OAUTH_REDIRECT_WEB', defaultValue: '');
const _supabaseUrlDefine =
    String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const _supabasePublishableApiKeyDefine =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_API_KEY', defaultValue: '');
const _supabaseAnonKeyDefine =
    String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
const _stripePublishableKeyDefine =
    String.fromEnvironment('STRIPE_PUBLISHABLE_KEY', defaultValue: '');
const _stripeMerchantDisplayNameDefine =
    String.fromEnvironment('STRIPE_MERCHANT_DISPLAY_NAME', defaultValue: '');

class EnvResolver {
  static String _resolveWithDefine({
    required String envKey,
    required String defineValue,
  }) {
    final normalizedDefine = defineValue.trim();
    if (normalizedDefine.isNotEmpty) return normalizedDefine;
    if (kReleaseMode) return '';
    return _readEnv(envKey);
  }

  static String _readEnv(String key) {
    final value = dotenv.maybeGet(key);
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
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

  static String get supabasePublicApiKey {
    final publishable = _resolveWithDefine(
      envKey: 'SUPABASE_PUBLISHABLE_API_KEY',
      defineValue: _supabasePublishableApiKeyDefine,
    );
    if (publishable.isNotEmpty) return publishable;
    return _resolveWithDefine(
      envKey: 'SUPABASE_ANON_KEY',
      defineValue: _supabaseAnonKeyDefine,
    );
  }

  static String get apiBaseUrl => _resolveWithDefine(
        envKey: 'API_BASE_URL',
        defineValue: _apiBaseUrlDefine,
      );

  static String get oauthRedirectWeb => _resolveWithDefine(
        envKey: 'OAUTH_REDIRECT_WEB',
        defineValue: _oauthRedirectWebDefine,
      );

  static String get oauthRedirectMobile => _readEnv('OAUTH_REDIRECT_MOBILE');

  static String get stripePublishableKey => _resolveWithDefine(
        envKey: 'STRIPE_PUBLISHABLE_KEY',
        defineValue: _stripePublishableKeyDefine,
      );

  static String get stripeMerchantDisplayName => _resolveWithDefine(
        envKey: 'STRIPE_MERCHANT_DISPLAY_NAME',
        defineValue: _stripeMerchantDisplayNameDefine,
      );

  static bool get subscriptionsEnabled {
    final raw = _readEnv('SUBSCRIPTIONS_ENABLED');
    return (raw.isEmpty ? 'false' : raw).toLowerCase() == 'true';
  }

  static bool get imageLoggingEnabled {
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
      'source=${kReleaseMode ? 'dart-define-only' : 'dart-define>dotenv'}',
    );
  }

  static String _logValue(String value) => value.isEmpty ? '(empty)' : value;
}
