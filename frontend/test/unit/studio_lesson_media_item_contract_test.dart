import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/studio/data/studio_models.dart';

void main() {
  test(
    'StudioLessonMediaItem parses canonical backend-authored media object',
    () {
      final item = StudioLessonMediaItem.fromResponse({
        'lesson_media_id': 'lesson-media-1',
        'lesson_id': 'lesson-1',
        'media_asset_id': 'media-1',
        'position': 1,
        'media_type': 'document',
        'state': 'ready',
        'media': {
          'media_id': 'media-1',
          'state': 'ready',
          'resolved_url': 'https://cdn.test/guide.pdf',
        },
      });

      expect(item.mediaAssetId, 'media-1');
      expect(item.media, isNotNull);
      expect(item.media!.mediaId, 'media-1');
      expect(item.media!.state, 'ready');
      expect(item.media!.resolvedUrl, 'https://cdn.test/guide.pdf');
    },
  );

  test('StudioLessonMediaItem keeps media null when backend omits it', () {
    final item = StudioLessonMediaItem.fromResponse({
      'lesson_media_id': 'lesson-media-2',
      'lesson_id': 'lesson-1',
      'media_asset_id': 'media-2',
      'position': 2,
      'media_type': 'audio',
      'state': 'uploaded',
      'media': null,
    });

    expect(item.mediaAssetId, 'media-2');
    expect(item.media, isNull);
  });

  test('StudioLessonMediaItem parses canonical placement response', () {
    final item = StudioLessonMediaItem.fromPlacementResponse({
      'lesson_media_id': 'lesson-media-3',
      'lesson_id': 'lesson-1',
      'media_asset_id': 'media-3',
      'position': 3,
      'media_type': 'image',
      'asset_state': 'ready',
      'media': {
        'media_id': 'media-3',
        'state': 'ready',
        'resolved_url': 'https://cdn.test/image.webp',
      },
    });

    expect(item.lessonMediaId, 'lesson-media-3');
    expect(item.state, 'ready');
    expect(item.previewReady, isTrue);
    expect(item.media?.resolvedUrl, 'https://cdn.test/image.webp');
  });
}
