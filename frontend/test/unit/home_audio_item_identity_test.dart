import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/home/data/home_audio_repository.dart';

void main() {
  group('HomeAudioItem.id', () {
    test('prefers profile_media_id and is independent of title', () {
      final original = HomeAudioItem(
        lessonMediaId: 'lesson-media-id',
        profileMediaId: '  profile-media-id  ',
        mediaId: 'media-id',
        title: 'Before rename',
        lessonId: 'lesson-id',
        lessonTitle: '',
        courseId: 'course-id',
        courseTitle: 'Course',
        kind: 'audio',
      );

      final renamed = HomeAudioItem(
        lessonMediaId: 'lesson-media-id',
        profileMediaId: '  profile-media-id  ',
        mediaId: 'media-id',
        title: 'After rename',
        lessonId: 'lesson-id',
        lessonTitle: '',
        courseId: 'course-id',
        courseTitle: 'Course',
        kind: 'audio',
      );

      expect(original.id, equals('profile-media-id'));
      expect(renamed.id, equals('profile-media-id'));
    });

    test('falls back to media_id when profile_media_id is missing', () {
      final item = HomeAudioItem(
        lessonMediaId: 'lesson-media-id',
        profileMediaId: null,
        mediaId: '  media-id  ',
        title: 'Title',
        lessonId: 'lesson-id',
        lessonTitle: '',
        courseId: 'course-id',
        courseTitle: 'Course',
        kind: 'audio',
      );

      expect(item.id, equals('media-id'));
    });

    test(
      'falls back to lesson_media id when both profile/media ids missing',
      () {
        final item = HomeAudioItem(
          lessonMediaId: '  lesson-media-id  ',
          profileMediaId: null,
          mediaId: null,
          title: 'Title',
          lessonId: 'lesson-id',
          lessonTitle: '',
          courseId: 'course-id',
          courseTitle: 'Course',
          kind: 'audio',
        );

        expect(item.id, equals('lesson-media-id'));
      },
    );
  });
}
