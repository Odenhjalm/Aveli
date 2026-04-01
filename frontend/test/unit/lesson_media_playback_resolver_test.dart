import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
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
  int lessonPlaybackCalls = 0;

  @override
  Future<String> fetchLessonPlaybackUrl(String lessonMediaId) async {
    lessonPlaybackCalls += 1;
    return _playbackUrl;
  }
}

LessonMediaItem _lessonMediaItem({
  required String id,
  required String mediaType,
  required String state,
  required bool previewReady,
  String? originalName,
}) {
  return LessonMediaItem(
    id: id,
    lessonId: 'lesson-1',
    mediaAssetId: 'asset-1',
    position: 1,
    mediaType: mediaType,
    state: state,
    originalName: originalName ?? '$id.$mediaType',
    previewReady: previewReady,
  );
}

void main() {
  group('Lesson media playback resolver', () {
    test('returns the backend-authored playback URL for ready audio', () async {
      final pipelineRepository = _FakeMediaPipelineRepository(
        'https://cdn.example.com/audio.mp3',
      );

      final resolved = await resolveLessonMediaPlaybackUrl(
        item: _lessonMediaItem(
          id: 'lesson-media-audio',
          mediaType: 'audio',
          state: 'ready',
          previewReady: true,
        ),
        pipelineRepository: pipelineRepository,
      );

      expect(resolved, 'https://cdn.example.com/audio.mp3');
      expect(pipelineRepository.lessonPlaybackCalls, 1);
    });

    test('fails before playback lookup when media is not ready', () async {
      final pipelineRepository = _FakeMediaPipelineRepository(
        'https://cdn.example.com/audio.mp3',
      );

      await expectLater(
        () => resolveLessonMediaPlaybackUrl(
          item: _lessonMediaItem(
            id: 'lesson-media-audio',
            mediaType: 'audio',
            state: 'processing',
            previewReady: false,
          ),
          pipelineRepository: pipelineRepository,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Lektionsmedia är inte klart för uppspelning: lesson-media-audio.',
          ),
        ),
      );
      expect(pipelineRepository.lessonPlaybackCalls, 0);
    });

    test('fails when a document is sent through the playback path', () async {
      final pipelineRepository = _FakeMediaPipelineRepository(
        'https://cdn.example.com/guide.pdf',
      );

      await expectLater(
        () => resolveLessonMediaPlaybackUrl(
          item: _lessonMediaItem(
            id: 'lesson-media-document',
            mediaType: 'document',
            state: 'ready',
            previewReady: true,
            originalName: 'guide.pdf',
          ),
          pipelineRepository: pipelineRepository,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Dokument får inte behandlas som uppspelningsmedia: '
                'lesson-media-document.',
          ),
        ),
      );
      expect(pipelineRepository.lessonPlaybackCalls, 0);
    });

    test(
      'documents resolve through the signed lesson-media contract',
      () async {
        final pipelineRepository = _FakeMediaPipelineRepository(
          'https://cdn.example.com/guide.pdf',
        );

        final resolved = await resolveLessonMediaDocumentUrl(
          item: _lessonMediaItem(
            id: 'lesson-media-document',
            mediaType: 'document',
            state: 'ready',
            previewReady: true,
            originalName: 'guide.pdf',
          ),
          pipelineRepository: pipelineRepository,
        );

        expect(resolved, 'https://cdn.example.com/guide.pdf');
        expect(pipelineRepository.lessonPlaybackCalls, 1);
      },
    );
  });
}
