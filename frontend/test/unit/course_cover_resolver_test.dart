import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/shared/utils/course_cover_contract.dart';
import 'package:aveli/shared/utils/course_cover_resolver.dart';

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
  group('resolveCourseCover', () {
    test('uses resolved control-plane cover when available', () {
      final repository = _buildRepository();

      final resolved = resolveCourseCover(
        mediaRepository: repository,
        cover: const CourseCoverData(
          mediaId: 'media-1',
          state: 'ready',
          resolvedUrl: '/api/files/public-media/course-cover.png',
          source: 'control_plane',
        ),
        legacyCoverUrl: '/api/files/public-media/legacy-cover.png',
        preferResolvedContract: true,
        debugContext: 'unit-control-plane',
      );

      expect(
        resolved.imageUrl,
        'https://api.example.com/api/files/public-media/course-cover.png',
      );
      expect(resolved.backendSource, 'control_plane');
      expect(resolved.usedLegacyCompatibility, isFalse);
      expect(resolved.usedPlaceholder, isFalse);
    });

    test('uses backend legacy fallback cover when provided by the contract', () {
      final repository = _buildRepository();

      final resolved = resolveCourseCover(
        mediaRepository: repository,
        cover: const CourseCoverData(
          mediaId: 'media-2',
          state: 'legacy_fallback',
          resolvedUrl: '/api/files/public-media/backend-legacy-cover.png',
          source: 'legacy_cover_url',
        ),
        legacyCoverUrl: '/api/files/public-media/raw-legacy-cover.png',
        preferResolvedContract: true,
        debugContext: 'unit-backend-legacy',
      );

      expect(
        resolved.imageUrl,
        'https://api.example.com/api/files/public-media/backend-legacy-cover.png',
      );
      expect(resolved.backendSource, 'legacy_cover_url');
      expect(resolved.usedLegacyCompatibility, isFalse);
      expect(resolved.usedPlaceholder, isFalse);
    });

    test('falls back to legacy cover url when the new contract is absent', () {
      final repository = _buildRepository();

      final resolved = resolveCourseCover(
        mediaRepository: repository,
        legacyCoverUrl: '/api/files/public-media/legacy-cover.png',
        preferResolvedContract: true,
        debugContext: 'unit-legacy-absent',
      );

      expect(
        resolved.imageUrl,
        'https://api.example.com/api/files/public-media/legacy-cover.png',
      );
      expect(resolved.backendSource, isNull);
      expect(resolved.usedLegacyCompatibility, isTrue);
      expect(resolved.usedPlaceholder, isFalse);
    });

    test('returns placeholder when no contract or legacy cover exists', () {
      final repository = _buildRepository();

      final resolved = resolveCourseCover(
        mediaRepository: repository,
        preferResolvedContract: true,
        debugContext: 'unit-placeholder',
      );

      expect(resolved.imageUrl, isNull);
      expect(resolved.usedLegacyCompatibility, isFalse);
      expect(resolved.usedPlaceholder, isTrue);
    });

    test(
      'does not fall back to raw legacy cover when the new contract is present but invalid',
      () {
        final repository = _buildRepository();

        final resolved = resolveCourseCover(
          mediaRepository: repository,
          cover: const CourseCoverData(
            mediaId: 'media-3',
            state: 'failed',
            resolvedUrl: null,
            source: 'placeholder',
          ),
          legacyCoverUrl: '/api/files/public-media/legacy-cover.png',
          preferResolvedContract: true,
          debugContext: 'unit-invalid-contract',
        );

        expect(resolved.imageUrl, isNull);
        expect(resolved.backendSource, 'placeholder');
        expect(resolved.usedLegacyCompatibility, isFalse);
        expect(resolved.usedPlaceholder, isTrue);
      },
    );

    test('keeps legacy behavior when the feature flag path is disabled', () {
      final repository = _buildRepository();

      final resolved = resolveCourseCover(
        mediaRepository: repository,
        cover: const CourseCoverData(
          mediaId: 'media-4',
          state: 'ready',
          resolvedUrl: '/api/files/public-media/course-cover.png',
          source: 'control_plane',
        ),
        legacyCoverUrl: '/api/files/public-media/legacy-cover.png',
        preferResolvedContract: false,
        debugContext: 'unit-flag-off',
      );

      expect(
        resolved.imageUrl,
        'https://api.example.com/api/files/public-media/legacy-cover.png',
      );
      expect(resolved.usedLegacyCompatibility, isTrue);
      expect(resolved.usedPlaceholder, isFalse);
    });
  });
}
