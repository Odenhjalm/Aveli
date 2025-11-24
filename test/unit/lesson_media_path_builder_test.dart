import 'package:flutter_test/flutter_test.dart';

import 'package:wisdom/features/studio/data/lesson_media_path.dart';

void main() {
  group('LessonMediaPathBuilder', () {
    test('bucketFor returns public bucket for intro lessons', () {
      final builder = LessonMediaPathBuilder();
      expect(builder.bucketFor(isIntro: true), 'public-media');
      expect(builder.bucketFor(isIntro: false), 'course-media');
    });

    test('buildPath sanitizes filename and includes timestamp', () {
      final builder = LessonMediaPathBuilder(timestampBuilder: () => 42);
      final path = builder.buildPath(
        courseId: 'course-1',
        lessonId: 'lesson-2',
        filename: 'My File.JPG',
      );
      expect(path, 'course-1/lesson-2/42_my_file.jpg');
    });

    test('kindFromContentType maps known content types', () {
      final builder = LessonMediaPathBuilder();
      expect(builder.kindFromContentType('image/png'), 'image');
      expect(builder.kindFromContentType('video/mp4'), 'video');
      expect(builder.kindFromContentType('audio/mpeg'), 'audio');
      expect(builder.kindFromContentType('application/pdf'), 'pdf');
      expect(builder.kindFromContentType('application/octet-stream'), 'other');
    });
  });
}
