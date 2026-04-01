import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aveli/features/studio/data/studio_models.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/presentation/lesson_media_preview_cache.dart';

class _MockStudioRepository extends Mock implements StudioRepository {}

StudioLessonMediaPreviewBatch _batch(List<StudioLessonMediaPreviewItem> items) {
  return StudioLessonMediaPreviewBatch(items: items);
}

void main() {
  test(
    'preview cache stores ready previews from the backend response',
    () async {
      final studioRepository = _MockStudioRepository();
      when(() => studioRepository.fetchLessonMediaPreviews(any())).thenAnswer(
        (_) async => _batch([
          const StudioLessonMediaPreviewItem(
            lessonMediaId: 'media-1',
            mediaType: 'image',
            authoritativeEditorReady: true,
            previewUrl: 'https://cdn.test/backend-preview.webp',
            fileName: 'image.png',
          ),
        ]),
      );

      final cache = LessonMediaPreviewCache(studioRepository: studioRepository);
      final preview = await cache.getPreview('media-1');

      expect(preview?.visualUrl, 'https://cdn.test/backend-preview.webp');
      expect(
        cache.peek('media-1')?.visualUrl,
        'https://cdn.test/backend-preview.webp',
      );
      expect(cache.peekStatus('media-1')?.state, LessonMediaPreviewState.ready);

      final cachedPreview = await cache.getSettledOrFetch('media-1');
      expect(cachedPreview?.visualUrl, 'https://cdn.test/backend-preview.webp');
      verify(
        () => studioRepository.fetchLessonMediaPreviews(['media-1']),
      ).called(1);
    },
  );

  test(
    'preview cache exposes loading while a backend request is in flight',
    () async {
      final studioRepository = _MockStudioRepository();
      final completer = Completer<StudioLessonMediaPreviewBatch>();
      when(
        () => studioRepository.fetchLessonMediaPreviews(any()),
      ).thenAnswer((_) => completer.future);

      final cache = LessonMediaPreviewCache(studioRepository: studioRepository);
      final previewFuture = cache.getPreview('media-1');
      await Future<void>.delayed(Duration.zero);

      expect(
        cache.peekStatus('media-1')?.state,
        LessonMediaPreviewState.loading,
      );

      completer.complete(
        _batch([
          const StudioLessonMediaPreviewItem(
            lessonMediaId: 'media-1',
            mediaType: 'image',
            authoritativeEditorReady: true,
            previewUrl: 'https://cdn.test/backend-preview.webp',
            fileName: 'image.png',
          ),
        ]),
      );

      final preview = await previewFuture;
      expect(preview?.visualUrl, 'https://cdn.test/backend-preview.webp');
      expect(cache.peekStatus('media-1')?.state, LessonMediaPreviewState.ready);
    },
  );

  test(
    'preview cache surfaces request failure as explicit failed state',
    () async {
      final studioRepository = _MockStudioRepository();
      final requestError = DioException(
        requestOptions: RequestOptions(path: '/api/media/previews'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/media/previews'),
          statusCode: 405,
          data: {'detail': 'Method Not Allowed'},
        ),
        type: DioExceptionType.badResponse,
      );
      when(
        () => studioRepository.fetchLessonMediaPreviews(any()),
      ).thenThrow(requestError);

      final cache = LessonMediaPreviewCache(studioRepository: studioRepository);

      await expectLater(
        cache.getPreview('media-1'),
        throwsA(isA<DioException>()),
      );
      final status = cache.peekStatus('media-1');
      expect(status?.state, LessonMediaPreviewState.failed);
      expect(status?.failureKind, LessonMediaPreviewFailureKind.unresolved);
      expect(status?.failureReason, 'preview_resolution_request_failed');
    },
  );

  test(
    'preview cache keeps valid and unresolved items distinct in one batch',
    () async {
      final studioRepository = _MockStudioRepository();
      when(() => studioRepository.fetchLessonMediaPreviews(any())).thenAnswer(
        (_) async => _batch([
          const StudioLessonMediaPreviewItem(
            lessonMediaId: 'media-valid',
            mediaType: 'image',
            authoritativeEditorReady: true,
            previewUrl: 'https://cdn.test/media-valid.webp',
            fileName: 'valid.png',
          ),
          const StudioLessonMediaPreviewItem(
            lessonMediaId: 'media-invalid',
            mediaType: 'image',
            authoritativeEditorReady: false,
            fileName: 'broken.png',
            failureReason: 'not_found',
          ),
        ]),
      );

      final cache = LessonMediaPreviewCache(studioRepository: studioRepository);
      final previews = await Future.wait([
        cache.getPreview('media-valid'),
        cache.getPreview('media-invalid'),
      ]);

      expect(previews[0]?.visualUrl, 'https://cdn.test/media-valid.webp');
      expect(previews[1]?.visualUrl, isNull);
      expect(
        cache.peekStatus('media-valid')?.state,
        LessonMediaPreviewState.ready,
      );
      expect(
        cache.peekStatus('media-invalid')?.state,
        LessonMediaPreviewState.failed,
      );
      expect(cache.peekStatus('media-invalid')?.failureReason, 'not_found');
    },
  );

  test('preview cache rejects empty lesson media ids', () async {
    final cache = LessonMediaPreviewCache(
      studioRepository: _MockStudioRepository(),
    );

    await expectLater(
      cache.getPreview(''),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Lesson media preview kräver lessonMediaId.',
        ),
      ),
    );
  });
}
