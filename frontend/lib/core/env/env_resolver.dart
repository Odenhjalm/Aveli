import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Environment resolution for Flutter Web + mobile/desktop.
///
/// ## Why this exists
/// Flutter Web has no runtime process environment. Any configuration must be
/// provided at **build time** via `--dart-define` / `--dart-define-from-file`
/// and is compiled into the JS bundle via `String.fromEnvironment`.
///
/// Non-web builds can additionally read configuration at runtime (e.g. a dotenv
/// asset file for local dev).
///
/// Previous code mixed these sources implicitly and duplicated required-key
/// validation in `main.dart`, making it easy to validate Web as if it had a
/// runtime environment. This could surface a false red “missing keys” banner
/// even when the compiled values were correct.
///
/// ## Design
/// EnvResolver is explicitly platform-aware:
/// - **Web:** compile-time only (dart-define).
/// - **Non-web:** runtime-first (dotenv), with compile-time fallback.
///
/// Validation uses the **same strategy** as resolution so it can’t drift.
///
/// To add a new required key, update `_requiredKeys` once.
enum EnvResolutionMode { compileTime, runtime }

@immutable
class EnvValidationResult {
  const EnvValidationResult({required this.mode, required this.missingKeys});

  final EnvResolutionMode mode;
  final List<String> missingKeys;

  bool get ok => missingKeys.isEmpty;
}

@immutable
class _RequiredKey {
  const _RequiredKey({
    required this.displayName,
    required this.keys,
    this.requiredOnWeb = true,
    this.requiredOnNonWeb = true,
  });

  final String displayName;
  final List<String> keys;
  final bool requiredOnWeb;
  final bool requiredOnNonWeb;
}

class EnvResolver {
  EnvResolver._();

  // Required keys are declared once and validated from the same resolver that
  // produces the values (prevents Web/runtime confusion).
  static const List<_RequiredKey> _requiredKeys = [
    _RequiredKey(displayName: 'API_BASE_URL', keys: ['API_BASE_URL']),
    _RequiredKey(
      displayName: 'STRIPE_PUBLISHABLE_KEY',
      keys: ['STRIPE_PUBLISHABLE_KEY'],
    ),
    _RequiredKey(displayName: 'SUPABASE_URL', keys: ['SUPABASE_URL']),
    _RequiredKey(
      displayName: 'SUPABASE_PUBLISHABLE_API_KEY/SUPABASE_PUBLIC_API_KEY',
      keys: ['SUPABASE_PUBLISHABLE_API_KEY', 'SUPABASE_PUBLIC_API_KEY'],
    ),
    _RequiredKey(
      displayName: 'OAUTH_REDIRECT_WEB',
      keys: ['OAUTH_REDIRECT_WEB'],
      requiredOnNonWeb: false,
    ),
    _RequiredKey(
      displayName: 'OAUTH_REDIRECT_MOBILE',
      keys: ['OAUTH_REDIRECT_MOBILE'],
      requiredOnWeb: false,
    ),
  ];

  static const Map<String, String> _compileTime = {
    // Cache-busting / deploy metadata (set in CI).
    'BUILD_NUMBER': String.fromEnvironment('BUILD_NUMBER'),
    'API_BASE_URL': String.fromEnvironment('API_BASE_URL'),
    'FRONTEND_URL': String.fromEnvironment('FRONTEND_URL'),
    'OAUTH_REDIRECT_WEB': String.fromEnvironment('OAUTH_REDIRECT_WEB'),
    'OAUTH_REDIRECT_MOBILE': String.fromEnvironment('OAUTH_REDIRECT_MOBILE'),
    'SUPABASE_URL': String.fromEnvironment('SUPABASE_URL'),
    'SUPABASE_PUBLISHABLE_API_KEY': String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_API_KEY',
    ),
    'SUPABASE_PUBLIC_API_KEY': String.fromEnvironment(
      'SUPABASE_PUBLIC_API_KEY',
    ),
    'STRIPE_PUBLISHABLE_KEY': String.fromEnvironment('STRIPE_PUBLISHABLE_KEY'),
    'STRIPE_MERCHANT_DISPLAY_NAME': String.fromEnvironment(
      'STRIPE_MERCHANT_DISPLAY_NAME',
    ),
    'SUBSCRIPTIONS_ENABLED': String.fromEnvironment('SUBSCRIPTIONS_ENABLED'),
    'IMAGE_LOGGING': String.fromEnvironment('IMAGE_LOGGING'),
  };

  static EnvResolutionMode get mode {
    // Web must be configured at build time (dart-define); dotenv is not a
    // production-capable mechanism there.
    if (kIsWeb) return EnvResolutionMode.compileTime;
    // Non-web can read configuration at runtime (dotenv / process env).
    return EnvResolutionMode.runtime;
  }

  static String _readCompileTime(String key) {
    final value = _compileTime[key];
    if (value == null) return '';
    final trimmed = value.trim();
    return trimmed;
  }

  static String _readRuntime(String key) {
    String? value;
    if (dotenv.isInitialized) {
      value = dotenv.maybeGet(key);
    }
    value ??= Platform.environment[key];
    if (value != null && value.trim().isNotEmpty) return value.trim();
    return '';
  }

  static String _readFirstNonEmpty(Iterable<String> keys) {
    return _readFirstNonEmptyWithReader(keys, _read);
  }

  static String _readFirstNonEmptyWithReader(
    Iterable<String> keys,
    String Function(String key) read,
  ) {
    for (final key in keys) {
      final value = read(key);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _read(String key) {
    switch (mode) {
      case EnvResolutionMode.compileTime:
        return _readCompileTime(key);
      case EnvResolutionMode.runtime:
        // Runtime-first (dotenv), with compile-time fallback.
        final runtimeValue = _readRuntime(key);
        if (runtimeValue.isNotEmpty) return runtimeValue;
        return _readCompileTime(key);
    }
  }

  static EnvValidationResult validateRequired({
    bool assertOnWebInDebug = true,
  }) {
    final isWeb = kIsWeb;
    final result = validateRequiredWithReader(
      isWeb: isWeb,
      mode: mode,
      read: _read,
    );

    if (assertOnWebInDebug &&
        isWeb &&
        kDebugMode &&
        result.missingKeys.isNotEmpty) {
      assert(() {
        throw AssertionError(
          'Missing required Web build-time env keys: ${result.missingKeys.join(', ')}. '
          'Provide them via --dart-define/--dart-define-from-file.',
        );
      }());
    }

    return result;
  }

  @visibleForTesting
  static EnvValidationResult validateRequiredWithReader({
    required bool isWeb,
    required EnvResolutionMode mode,
    required String Function(String key) read,
  }) {
    final missing = <String>[];
    for (final required in _requiredKeys) {
      final isRequired = isWeb
          ? required.requiredOnWeb
          : required.requiredOnNonWeb;
      if (!isRequired) continue;
      final value = _readFirstNonEmptyWithReader(required.keys, read);
      if (value.isEmpty) {
        missing.add(required.displayName);
      }
    }
    return EnvValidationResult(mode: mode, missingKeys: missing);
  }

  static String get frontendUrl => _readFirstNonEmpty(const ['FRONTEND_URL']);

  static String get buildNumber => _readFirstNonEmpty(const ['BUILD_NUMBER']);

  static String get supabaseUrl => _readFirstNonEmpty(const ['SUPABASE_URL']);

  static String get supabasePublishableKey {
    return _readFirstNonEmpty(const [
      'SUPABASE_PUBLISHABLE_API_KEY',
      'SUPABASE_PUBLIC_API_KEY',
    ]);
  }

  static String get apiBaseUrl => _readFirstNonEmpty(const ['API_BASE_URL']);

  static String get oauthRedirectWeb =>
      _readFirstNonEmpty(const ['OAUTH_REDIRECT_WEB']);

  static String get oauthRedirectMobile =>
      _readFirstNonEmpty(const ['OAUTH_REDIRECT_MOBILE']);

  static String get stripePublishableKey =>
      _readFirstNonEmpty(const ['STRIPE_PUBLISHABLE_KEY']);

  static String get stripeMerchantDisplayName =>
      _readFirstNonEmpty(const ['STRIPE_MERCHANT_DISPLAY_NAME']);

  static bool get subscriptionsEnabled {
    final raw = _read('SUBSCRIPTIONS_ENABLED');
    return (raw.isEmpty ? 'false' : raw).toLowerCase() == 'true';
  }

  static bool get imageLoggingEnabled {
    final raw = _read('IMAGE_LOGGING');
    return (raw.isEmpty ? 'true' : raw).toLowerCase() != 'false';
  }

  static void debugLogResolved() {
    if (!kDebugMode) return;
    debugPrint(
      'EnvResolver (${mode.name}) resolved: '
      'apiBaseUrl=${_logValue(apiBaseUrl)} '
      'frontendUrl=${_logValue(frontendUrl)} '
      'oauthRedirectWeb=${_logValue(oauthRedirectWeb)} '
      'oauthRedirectMobile=${_logValue(oauthRedirectMobile)} '
      'supabaseUrl=${_logValue(supabaseUrl)} '
      'stripeKey=${_logValue(stripePublishableKey)} '
      'source=${mode == EnvResolutionMode.runtime ? 'dotenv>dart-define' : 'dart-define-only'}',
    );
  }

  static String _logValue(String value) => value.isEmpty ? '(empty)' : value;
}
