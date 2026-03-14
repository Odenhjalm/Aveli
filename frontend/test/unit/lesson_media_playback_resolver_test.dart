import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/shared/utils/lesson_media_playback_resolver.dart';

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

class _FakeMediaPipelineRepository extends MediaPipelineRepository {
  _FakeMediaPipelineRepository(this._playbackUrl)
    : super(
        client: ApiClient(
          baseUrl: 'https://api.example.com',
          tokenStorage: _FakeTokenStorage(),
        ),
      );

  final String _playbackUrl;

  @override
  Future<String> fetchLessonPlaybackUrl(String lessonMediaId) async =>
      _playbackUrl;
}

MediaRepository _buildMediaRepository() {
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

const _lessonMediaItem = LessonMediaItem(
  id: 'lesson-media-1',
  kind: 'audio',
  storagePath: 'unused',
);

void main() {
  group('Lesson media playback resolver', () {
    test('returns a valid https playback URL', () async {
      final resolved = await resolveLessonMediaPlaybackUrl(
        item: _lessonMediaItem,
        mediaRepository: _buildMediaRepository(),
        pipelineRepository: _FakeMediaPipelineRepository(
          'https://cdn.example.com/audio.mp3',
        ),
      );

      expect(resolved, 'https://cdn.example.com/audio.mp3');
    });

    test('rejects non-http playback URLs', () async {
      final resolved = await resolveLessonMediaPlaybackUrl(
        item: _lessonMediaItem,
        mediaRepository: _buildMediaRepository(),
        pipelineRepository: _FakeMediaPipelineRepository('javascript:alert(1)'),
      );

      expect(resolved, isNull);
    });
  });
}
