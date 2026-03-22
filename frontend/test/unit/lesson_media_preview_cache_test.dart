import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';

import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/presentation/lesson_media_preview_cache.dart';

class _MockStudioRepository extends Mock implements StudioRepository {}

void main() {
  test(
    'preview cache always revalidates visual URLs via backend authority',
    () async {
      final studioRepository = _MockStudioRepository();
      final responses = <Map<String, Map<String, dynamic>>>[
        {
          'media-1': {
            'media_type': 'image',
            'resolved_preview_url': 'https://cdn.test/backend-preview-1.webp',
            'file_name': 'image.png',
          },
        },
        {
          'media-1': {
            'media_type': 'image',
            'resolved_preview_url': 'https://cdn.test/backend-preview-2.webp',
            'file_name': 'image.png',
          },
        },
      ];
      var callCount = 0;
      when(() => studioRepository.fetchLessonMediaPreviews(any())).thenAnswer((
        _,
      ) async {
        final response = responses[callCount];
        callCount += 1;
        return response;
      });

      final cache = LessonMediaPreviewCache(
        studioRepository: studioRepository,
        transientResolverMaxRetries: 0,
      );
      cache.primeFromLessonMedia([
        {
          'id': 'media-1',
          'kind': 'image',
          'thumbnail_url': 'https://cdn.test/row-thumb.webp',
          'original_name': 'image.png',
        },
      ]);

      final firstPreview = await cache.getPreview('media-1');
      final secondPreview = await cache.getPreview('media-1');

      expect(
        firstPreview?.visualUrl,
        'https://cdn.test/backend-preview-1.webp',
      );
      expect(
        secondPreview?.visualUrl,
        'https://cdn.test/backend-preview-2.webp',
      );
      verify(
        () => studioRepository.fetchLessonMediaPreviews(['media-1']),
      ).called(2);
    },
  );

  test(
    'preview cache keeps failed preview lookups retryable after contract failures',
    () async {
      final studioRepository = _MockStudioRepository();
      final telemetry = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          telemetry.add(message);
        }
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      when(() => studioRepository.fetchLessonMediaPreviews(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/media/previews'),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/media/previews'),
            statusCode: 405,
            data: {'detail': 'Method Not Allowed'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final cache = LessonMediaPreviewCache(
        studioRepository: studioRepository,
        transientResolverMaxRetries: 0,
      );
      cache.primeFromLessonMedia([
        {'id': 'media-image-1', 'kind': 'image', 'original_name': 'image.png'},
      ]);

      final firstPreview = await cache.getPreview('media-image-1');
      final secondPreview = await cache.getPreview('media-image-1');

      expect(firstPreview?.mediaType, 'image');
      expect(firstPreview?.visualUrl, isNull);
      expect(secondPreview?.mediaType, 'image');
      expect(secondPreview?.visualUrl, isNull);
      verify(
        () => studioRepository.fetchLessonMediaPreviews(['media-image-1']),
      ).called(2);
      expect(
        telemetry.any(
          (entry) =>
              entry.contains('LESSON_MEDIA_PREVIEW_ENDPOINT_CONTRACT_FAILURE'),
        ),
        isTrue,
      );
    },
  );

  test(
    'preview cache preserves successful ids when a sibling id fails in the same batch',
    () async {
      final studioRepository = _MockStudioRepository();
      when(() => studioRepository.fetchLessonMediaPreviews(any())).thenAnswer((
        _,
      ) async {
        return {
          'media-valid': {
            'media_type': 'image',
            'authoritative_editor_ready': true,
            'resolved_preview_url': 'https://cdn.test/media-valid.webp',
            'file_name': 'valid.png',
          },
          'media-invalid': {
            'media_type': 'image',
            'authoritative_editor_ready': false,
            'file_name': 'broken.png',
            'failure_reason': 'not_found',
          },
        };
      });

      final cache = LessonMediaPreviewCache(
        studioRepository: studioRepository,
        transientResolverMaxRetries: 0,
      );
      cache.primeFromLessonMedia([
        {'id': 'media-valid', 'kind': 'image', 'original_name': 'valid.png'},
        {'id': 'media-invalid', 'kind': 'image', 'original_name': 'broken.png'},
      ]);

      final previews = await Future.wait([
        cache.getPreview('media-valid'),
        cache.getPreview('media-invalid'),
      ]);

      expect(previews[0]?.visualUrl, 'https://cdn.test/media-valid.webp');
      expect(previews[0]?.authoritativeEditorReady, isTrue);
      expect(previews[1]?.visualUrl, isNull);
      expect(previews[1]?.authoritativeEditorReady, isFalse);
      expect(
        cache.peek('media-valid')?.visualUrl,
        'https://cdn.test/media-valid.webp',
      );
      expect(cache.peek('media-invalid')?.authoritativeEditorReady, isFalse);
      verify(
        () => studioRepository.fetchLessonMediaPreviews([
          'media-valid',
          'media-invalid',
        ]),
      ).called(1);
    },
  );

  test(
    'preview cache ignores stored image fallbacks when backend preview resolution fails',
    () async {
      final studioRepository = _MockStudioRepository();
      when(() => studioRepository.fetchLessonMediaPreviews(any())).thenAnswer((
        _,
      ) async {
        return {
          'media-image-1': {
            'media_type': 'image',
            'authoritative_editor_ready': false,
            'failure_reason': 'unresolvable',
          },
        };
      });

      final cache = LessonMediaPreviewCache(
        studioRepository: studioRepository,
        transientResolverMaxRetries: 0,
      );
      cache.primeFromLessonMedia([
        {
          'id': 'media-image-1',
          'kind': 'image',
          'preferredUrl': 'https://cdn.test/media-image-1.webp',
          'original_name': 'image.png',
        },
      ]);

      final preview = await cache.getPreview('media-image-1');

      expect(preview?.visualUrl, isNull);
      expect(preview?.authoritativeEditorReady, isFalse);
      verify(
        () => studioRepository.fetchLessonMediaPreviews(['media-image-1']),
      ).called(1);
    },
  );

  test(
    'preview cache keeps metadata-only images loading while a fetch is in flight',
    () async {
      final studioRepository = _MockStudioRepository();
      final completer = Completer<Map<String, Map<String, dynamic>>>();
      when(() => studioRepository.fetchLessonMediaPreviews(any())).thenAnswer((
        _,
      ) {
        return completer.future;
      });

      final cache = LessonMediaPreviewCache(studioRepository: studioRepository);
      cache.primeFromLessonMedia([
        {
          'id': 'media-image-1',
          'kind': 'image',
          'preferredUrl': 'https://cdn.test/media-image-1.webp',
          'original_name': 'image.png',
        },
      ]);

      final previewFuture = cache.getPreview('media-image-1');
      await Future<void>.delayed(Duration.zero);

      final inFlightStatus = cache.peekStatus('media-image-1');
      expect(inFlightStatus?.state, LessonMediaPreviewState.loading);
      expect(inFlightStatus?.visualUrl, isNull);

      completer.complete({
        'media-image-1': {
          'media_type': 'image',
          'authoritative_editor_ready': true,
          'resolved_preview_url': 'https://cdn.test/backend-image-1.webp',
          'file_name': 'image.png',
        },
      });

      final preview = await previewFuture;
      expect(preview?.visualUrl, 'https://cdn.test/backend-image-1.webp');
      expect(
        cache.peekStatus('media-image-1')?.state,
        LessonMediaPreviewState.ready,
      );
    },
  );

  test(
    'preview cache retries transient unresolved image previews before surfacing failure',
    () async {
      final studioRepository = _MockStudioRepository();
      var callCount = 0;
      final retryCompleter = Completer<Map<String, Map<String, dynamic>>>();
      when(() => studioRepository.fetchLessonMediaPreviews(any())).thenAnswer((
        _,
      ) {
        callCount += 1;
        if (callCount == 1) {
          return Future<Map<String, Map<String, dynamic>>>.value({
            'media-image-1': {
              'media_type': 'image',
              'authoritative_editor_ready': false,
              'failure_reason': 'unresolvable',
              'file_name': 'image.png',
            },
          });
        }
        return retryCompleter.future;
      });

      final cache = LessonMediaPreviewCache(
        studioRepository: studioRepository,
        transientResolverRetryDelay: const Duration(milliseconds: 1),
        transientResolverMaxRetries: 2,
      );
      cache.primeFromLessonMedia([
        {'id': 'media-image-1', 'kind': 'image', 'original_name': 'image.png'},
      ]);

      final previewFuture = cache.getPreview('media-image-1');
      await Future<void>.delayed(const Duration(milliseconds: 2));

      final retryingStatus = cache.peekStatus('media-image-1');
      expect(retryingStatus?.state, LessonMediaPreviewState.loading);
      expect(retryingStatus?.isRetrying, isTrue);

      retryCompleter.complete({
        'media-image-1': {
          'media_type': 'image',
          'authoritative_editor_ready': true,
          'resolved_preview_url': 'https://cdn.test/backend-image-1.webp',
          'file_name': 'image.png',
        },
      });
      final preview = await previewFuture;
      expect(preview?.visualUrl, 'https://cdn.test/backend-image-1.webp');
      expect(callCount, 2);
      expect(
        cache.peekStatus('media-image-1')?.state,
        LessonMediaPreviewState.ready,
      );
    },
  );

  test(
    'preview cache consumes failed transition logs once per data-level failure epoch',
    () async {
      final studioRepository = _MockStudioRepository();
      when(() => studioRepository.fetchLessonMediaPreviews(any())).thenAnswer((
        _,
      ) async {
        return {
          'media-image-1': {
            'media_type': 'image',
            'authoritative_editor_ready': false,
            'failure_reason': 'unresolvable',
          },
        };
      });

      final cache = LessonMediaPreviewCache(
        studioRepository: studioRepository,
        transientResolverMaxRetries: 0,
      );
      cache.primeFromLessonMedia([
        {'id': 'media-image-1', 'kind': 'image', 'original_name': 'image.png'},
      ]);

      await cache.getPreview('media-image-1');
      final firstFailed = cache.peekStatus('media-image-1');
      expect(firstFailed?.state, LessonMediaPreviewState.failed);
      expect(firstFailed?.failedTransitionVersion, 1);
      expect(
        cache.consumeFailedTransitionLog(
          'media-image-1',
          firstFailed!.failedTransitionVersion!,
        ),
        isTrue,
      );
      expect(
        cache.consumeFailedTransitionLog(
          'media-image-1',
          firstFailed.failedTransitionVersion!,
        ),
        isFalse,
      );

      cache.invalidate(['media-image-1']);
      expect(
        cache.peekStatus('media-image-1')?.state,
        LessonMediaPreviewState.loading,
      );

      await cache.getPreview('media-image-1');
      final secondFailed = cache.peekStatus('media-image-1');
      expect(secondFailed?.state, LessonMediaPreviewState.failed);
      expect(secondFailed?.failedTransitionVersion, 2);
      expect(
        cache.consumeFailedTransitionLog(
          'media-image-1',
          secondFailed!.failedTransitionVersion!,
        ),
        isTrue,
      );
    },
  );
}
