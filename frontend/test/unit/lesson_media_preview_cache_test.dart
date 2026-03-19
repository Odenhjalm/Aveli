import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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
}
