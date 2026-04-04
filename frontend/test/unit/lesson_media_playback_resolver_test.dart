import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/shared/utils/lesson_media_playback_resolver.dart';

LessonMediaItem _lessonMediaItem({
  required String id,
  required String mediaType,
}) {
  return LessonMediaItem(
    id: id,
    lessonId: 'lesson-1',
    mediaAssetId: 'asset-1',
    position: 1,
    mediaType: mediaType,
    state: 'ready',
    media: null,
  );
}

void main() {
  group('Lesson media type helpers', () {
    test('classifies canonical lesson media types', () {
      expect(
        lessonMediaTypeOf(
          _lessonMediaItem(id: 'lesson-media-audio', mediaType: 'audio'),
        ),
        CanonicalLessonMediaType.audio,
      );
      expect(
        lessonMediaTypeOf(
          _lessonMediaItem(id: 'lesson-media-image', mediaType: 'image'),
        ),
        CanonicalLessonMediaType.image,
      );
      expect(
        lessonMediaTypeOf(
          _lessonMediaItem(id: 'lesson-media-video', mediaType: 'video'),
        ),
        CanonicalLessonMediaType.video,
      );
      expect(
        lessonMediaTypeOf(
          _lessonMediaItem(id: 'lesson-media-document', mediaType: 'document'),
        ),
        CanonicalLessonMediaType.document,
      );
    });

    test('identifies canonical document lesson media', () {
      expect(
        isLessonMediaDocument(
          _lessonMediaItem(id: 'lesson-media-document', mediaType: 'document'),
        ),
        isTrue,
      );
      expect(
        isLessonMediaDocument(
          _lessonMediaItem(id: 'lesson-media-audio', mediaType: 'audio'),
        ),
        isFalse,
      );
    });

    test('rejects unknown lesson media types', () async {
      await expectLater(
        () async => lessonMediaTypeOf(
          _lessonMediaItem(id: 'lesson-media-unknown', mediaType: 'legacy'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Ogiltig lesson media_type "legacy" för lektionsmedia lesson-media-unknown.',
          ),
        ),
      );
    });
  });
}
