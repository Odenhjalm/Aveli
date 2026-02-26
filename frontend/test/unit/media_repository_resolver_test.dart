import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/features/media/data/media_repository.dart';

class _FakeTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> updateAccessToken(String accessToken) async {}
}

MediaRepository _buildRepository() {
  final client = ApiClient(
    baseUrl: 'https://api.example.com',
    tokenStorage: _FakeTokenStorage(),
  );
  return MediaRepository(
    client: client,
    config: const AppConfig(
      apiBaseUrl: 'https://api.example.com',
      stripePublishableKey: 'pk_test_123',
      stripeMerchantDisplayName: 'Aveli',
      subscriptionsEnabled: true,
      supabaseUrl: 'https://project.supabase.co',
    ),
  );
}

void main() {
  group('MediaRepository URL resolver', () {
    test('buildMediaUrl returns backend files path', () {
      final repository = _buildRepository();

      final resolved = repository.buildMediaUrl(
        'public-media',
        'course/lesson/file.png',
      );

      expect(resolved, '/api/files/public-media/course/lesson/file.png');
    });

    test('resolveDownloadUrl resolves backend-relative path', () {
      final repository = _buildRepository();

      final resolved = repository.resolveDownloadUrl(
        '/api/files/public-media/course/lesson/file.png',
      );

      expect(
        resolved,
        'https://api.example.com/api/files/public-media/course/lesson/file.png',
      );
    });

    test('resolveDownloadUrl rewrites Supabase public URL to backend resolver', () {
      final repository = _buildRepository();

      final resolved = repository.resolveDownloadUrl(
        'https://project.supabase.co/storage/v1/object/public/public-media/course/lesson/file.png',
      );

      expect(
        resolved,
        'https://api.example.com/api/files/public-media/course/lesson/file.png',
      );
    });

    test('resolvePlaybackUrl resolves signed backend stream path', () {
      final repository = _buildRepository();

      final resolved = repository.resolvePlaybackUrl(
        '/media/stream/signed-token',
      );

      expect(resolved, 'https://api.example.com/media/stream/signed-token');
    });

    test('blocks unresolved direct Supabase public URL usage', () {
      final repository = _buildRepository();

      expect(
        () => repository.resolveDownloadUrl(
          'https://cdn.test/storage/v1/object/public',
        ),
        throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
      );
    });
  });
}
