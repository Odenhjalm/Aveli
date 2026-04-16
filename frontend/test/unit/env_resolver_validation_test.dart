import 'package:aveli/core/env/env_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EnvResolver.validateRequiredWithReader', () {
    test('web: required keys satisfied (supports aliases)', () {
      final values = <String, String>{
        'API_BASE_URL': 'https://example.com',
        'STRIPE_PUBLISHABLE_KEY': 'pk_test_123',
        'OAUTH_REDIRECT_WEB': 'https://app.example.com/auth/callback',
        'SUBSCRIPTIONS_ENABLED': 'true',
      };

      final result = EnvResolver.validateRequiredWithReader(
        isWeb: true,
        mode: EnvResolutionMode.compileTime,
        read: (key) => values[key]?.trim() ?? '',
      );

      expect(result.ok, isTrue);
      expect(result.missingKeys, isEmpty);
    });

    test('web: requires OAUTH_REDIRECT_WEB (not mobile)', () {
      final values = <String, String>{
        'API_BASE_URL': 'https://example.com',
        'STRIPE_PUBLISHABLE_KEY': 'pk_test_123',
        'OAUTH_REDIRECT_MOBILE': 'aveliapp://auth/callback',
        'SUBSCRIPTIONS_ENABLED': 'true',
      };

      final result = EnvResolver.validateRequiredWithReader(
        isWeb: true,
        mode: EnvResolutionMode.compileTime,
        read: (key) => values[key]?.trim() ?? '',
      );

      expect(result.missingKeys, contains('OAUTH_REDIRECT_WEB'));
      expect(result.missingKeys, isNot(contains('OAUTH_REDIRECT_MOBILE')));
    });

    test('non-web: requires OAUTH_REDIRECT_MOBILE (not web)', () {
      final values = <String, String>{
        'API_BASE_URL': 'https://example.com',
        'STRIPE_PUBLISHABLE_KEY': 'pk_test_123',
        'OAUTH_REDIRECT_MOBILE': 'aveliapp://auth/callback',
        'SUBSCRIPTIONS_ENABLED': 'true',
      };

      final result = EnvResolver.validateRequiredWithReader(
        isWeb: false,
        mode: EnvResolutionMode.runtime,
        read: (key) => values[key]?.trim() ?? '',
      );

      expect(result.ok, isTrue);
      expect(result.missingKeys, isEmpty);
    });

    test('reports missing oauth redirect without requiring Supabase keys', () {
      final values = <String, String>{
        'API_BASE_URL': 'https://example.com',
        'STRIPE_PUBLISHABLE_KEY': 'pk_test_123',
        'SUBSCRIPTIONS_ENABLED': 'true',
      };

      final result = EnvResolver.validateRequiredWithReader(
        isWeb: true,
        mode: EnvResolutionMode.compileTime,
        read: (key) => values[key]?.trim() ?? '',
      );

      expect(result.missingKeys, contains('OAUTH_REDIRECT_WEB'));
    });

    test(
      'web: requires SUBSCRIPTIONS_ENABLED for compiled checkout config',
      () {
        final values = <String, String>{
          'API_BASE_URL': 'https://example.com',
          'STRIPE_PUBLISHABLE_KEY': 'pk_test_123',
          'OAUTH_REDIRECT_WEB': 'https://app.example.com/auth/callback',
        };

        final result = EnvResolver.validateRequiredWithReader(
          isWeb: true,
          mode: EnvResolutionMode.compileTime,
          read: (key) => values[key]?.trim() ?? '',
        );

        expect(result.missingKeys, contains('SUBSCRIPTIONS_ENABLED'));
      },
    );
  });
}
