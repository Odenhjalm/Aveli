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
    test('uses ready control-plane cover when available', () {
      final repository = _buildRepository();

      final resolved = resolveCourseCover(
        mediaRepository: repository,
        cover: const CourseCoverData(
          mediaId: 'media-1',
          state: 'ready',
          resolvedUrl: '/api/files/public-media/course-cover.png',
          source: 'control_plane',
        ),
        coverMediaId: 'media-1',
        debugContext: 'unit-control-plane',
      );

      expect(
        resolved.imageUrl,
        'https://api.example.com/api/files/public-media/course-cover.png',
      );
      expect(resolved.backendSource, 'control_plane');
      expect(resolved.usedPlaceholder, isFalse);
      expect(resolved.hadContractViolation, isFalse);
    });

    test(
      'returns placeholder and contract violation when canonical cover is not ready',
      () {
        final repository = _buildRepository();

        final resolved = resolveCourseCover(
          mediaRepository: repository,
          cover: const CourseCoverData(
            mediaId: 'media-2',
            state: 'processing',
            resolvedUrl: null,
            source: 'placeholder',
          ),
          coverMediaId: 'media-2',
          debugContext: 'unit-invalid-contract',
        );

        expect(resolved.imageUrl, isNull);
        expect(resolved.backendSource, 'placeholder');
        expect(resolved.usedPlaceholder, isTrue);
        expect(resolved.hadContractViolation, isTrue);
      },
    );

    test('returns placeholder without violation when no cover exists', () {
      final repository = _buildRepository();

      final resolved = resolveCourseCover(
        mediaRepository: repository,
        debugContext: 'unit-placeholder',
      );

      expect(resolved.imageUrl, isNull);
      expect(resolved.usedPlaceholder, isTrue);
      expect(resolved.hadContractViolation, isFalse);
    });

    test('ignores legacy cover_url payloads completely', () {
      final repository = _buildRepository();

      final resolved = resolveCourseMapCover(
        <String, dynamic>{
          'id': 'course-legacy',
          'cover_url': '/api/files/public-media/legacy-cover.png',
        },
        repository,
        debugContext: 'unit-legacy-ignored',
      );

      expect(resolved.imageUrl, isNull);
      expect(resolved.usedPlaceholder, isTrue);
      expect(resolved.hadContractViolation, isFalse);
    });

    test('allows explicit editor override previews when enabled', () {
      final repository = _buildRepository();

      final resolved = resolveCourseMapCover(
        <String, dynamic>{
          'id': 'course-editor',
          'cover_media_id': 'media-editor',
          'cover': <String, dynamic>{
            'media_id': 'media-editor',
            'state': 'uploaded',
            'resolved_url': '/api/files/public-media/editor-preview.png',
            'source': 'editor_override',
          },
        },
        repository,
        allowEditorOverride: true,
        debugContext: 'unit-editor-override',
      );

      expect(
        resolved.imageUrl,
        'https://api.example.com/api/files/public-media/editor-preview.png',
      );
      expect(resolved.backendSource, 'editor_override');
      expect(resolved.usedPlaceholder, isFalse);
      expect(resolved.hadContractViolation, isFalse);
    });
  });
}
