import 'package:aveli/core/env/env_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EnvResolver.validateRequiredWithReader', () {
    test('web: required keys satisfied (supports aliases)', () {
      final values = <String, String>{
        'API_BASE_URL': 'https://example.com',
        'STRIPE_PUBLISHABLE_KEY': 'pk_test_123',
        'SUPABASE_URL': 'https://supabase.example.com',
        'SUPABASE_PUBLIC_API_KEY': 'sb_publishable_123',
        'OAUTH_REDIRECT_WEB': 'https://app.example.com/auth/callback',
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
        'SUPABASE_URL': 'https://supabase.example.com',
        'SUPABASE_PUBLIC_API_KEY': 'sb_publishable_123',
        'OAUTH_REDIRECT_MOBILE': 'aveliapp://auth/callback',
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
        'SUPABASE_URL': 'https://supabase.example.com',
        'SUPABASE_PUBLISHABLE_API_KEY': 'sb_publishable_123',
        'OAUTH_REDIRECT_MOBILE': 'aveliapp://auth/callback',
      };

      final result = EnvResolver.validateRequiredWithReader(
        isWeb: false,
        mode: EnvResolutionMode.runtime,
        read: (key) => values[key]?.trim() ?? '',
      );

      expect(result.ok, isTrue);
      expect(result.missingKeys, isEmpty);
    });

    test('web: supports SUPABASE_ANON_KEY alias', () {
      final values = <String, String>{
        'API_BASE_URL': 'https://example.com',
        'STRIPE_PUBLISHABLE_KEY': 'pk_test_123',
        'SUPABASE_URL': 'https://supabase.example.com',
        'SUPABASE_ANON_KEY': 'sb_publishable_123',
        'OAUTH_REDIRECT_WEB': 'https://app.example.com/auth/callback',
      };

      final result = EnvResolver.validateRequiredWithReader(
        isWeb: true,
        mode: EnvResolutionMode.compileTime,
        read: (key) => values[key]?.trim() ?? '',
      );

      expect(result.ok, isTrue);
      expect(result.missingKeys, isEmpty);
    });

    test('reports missing supabase client key with combined display name', () {
      final values = <String, String>{
        'API_BASE_URL': 'https://example.com',
        'STRIPE_PUBLISHABLE_KEY': 'pk_test_123',
        'SUPABASE_URL': 'https://supabase.example.com',
        'OAUTH_REDIRECT_WEB': 'https://app.example.com/auth/callback',
      };

      final result = EnvResolver.validateRequiredWithReader(
        isWeb: true,
        mode: EnvResolutionMode.compileTime,
        read: (key) => values[key]?.trim() ?? '',
      );

      expect(
        result.missingKeys,
        contains(
          'SUPABASE_PUBLISHABLE_API_KEY/SUPABASE_PUBLIC_API_KEY/SUPABASE_ANON_KEY',
        ),
      );
    });
  });
}
