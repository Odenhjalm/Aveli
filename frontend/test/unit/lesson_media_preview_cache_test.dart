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

      final cache = LessonMediaPreviewCache(studioRepository: studioRepository);
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
    'preview cache stabilizes failed visual previews and suppresses repeated contract failures',
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

      final cache = LessonMediaPreviewCache(studioRepository: studioRepository);
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
      ).called(1);
      expect(
        telemetry.any(
          (entry) =>
              entry.contains('LESSON_MEDIA_PREVIEW_ENDPOINT_CONTRACT_FAILURE'),
        ),
        isTrue,
      );
      expect(
        telemetry.any(
          (entry) => entry.contains('LESSON_MEDIA_PLACEHOLDER_STABILIZED'),
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

      final cache = LessonMediaPreviewCache(studioRepository: studioRepository);
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
    'preview cache keeps a stored image fallback when backend preview resolution fails',
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

      final cache = LessonMediaPreviewCache(studioRepository: studioRepository);
      cache.primeFromLessonMedia([
        {
          'id': 'media-image-1',
          'kind': 'image',
          'preferredUrl': 'https://cdn.test/media-image-1.webp',
          'original_name': 'image.png',
        },
      ]);

      final preview = await cache.getPreview('media-image-1');

      expect(preview?.visualUrl, 'https://cdn.test/media-image-1.webp');
      expect(preview?.authoritativeEditorReady, isFalse);
      verify(
        () => studioRepository.fetchLessonMediaPreviews(['media-image-1']),
      ).called(1);
    },
  );
}
