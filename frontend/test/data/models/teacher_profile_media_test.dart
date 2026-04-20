import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/data/models/teacher_profile_media.dart';

void main() {
  test('parses canonical profile media payload without source catalogs', () {
    final payload = TeacherProfileMediaPayload.fromJson({'items': const []});

    expect(payload.items, isEmpty);
  });

  test('lesson source parsing does not require legacy storage fields', () {
    final source = TeacherProfileLessonSource.fromJson({
      'id': 'source-1',
      'lesson_id': 'lesson-1',
      'lesson_title': 'Lektion',
      'course_id': 'course-1',
      'course_title': 'Kurs',
      'course_slug': 'kurs',
      'kind': 'audio',
      'content_type': 'audio/mpeg',
      'duration_seconds': 12,
      'position': 1,
      'created_at': '2025-01-01T00:00:00.000Z',
      'media': null,
    });

    expect(source.id, 'source-1');
    expect(source.media, isNull);
  });

  test('rejects collapsed external identity in item parsing', () {
    expect(
      () => TeacherProfileMediaItem.fromJson({
        'id': 'media-1',
        'teacher_id': 'teacher-1',
        'media_kind': 'external',
        'lesson_media_id': 'lesson-media-1',
        'external_url': 'https://example.com/profile',
        'title': null,
        'description': null,
        'cover_media_id': null,
        'cover_image_url': null,
        'position': 0,
        'is_published': true,
        'enabled_for_home_player': false,
        'created_at': '2025-01-01T00:00:00.000Z',
        'updated_at': '2025-01-01T00:00:00.000Z',
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
