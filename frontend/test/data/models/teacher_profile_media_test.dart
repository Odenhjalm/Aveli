import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/data/models/teacher_profile_media.dart';

void main() {
  test('rejects missing required source catalogs in payload parsing', () {
    expect(
      () => TeacherProfileMediaPayload.fromJson({
        'items': const [],
        'lesson_media_sources': const [],
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects collapsed external identity in item parsing', () {
    expect(
      () => TeacherProfileMediaItem.fromJson({
        'id': 'media-1',
        'teacher_id': 'teacher-1',
        'media_kind': 'external',
        'lesson_media_id': 'lesson-media-1',
        'seminar_recording_id': null,
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
