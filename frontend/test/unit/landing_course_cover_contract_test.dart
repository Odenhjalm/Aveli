import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/landing/application/landing_providers.dart';

void main() {
  test('landing course section parses canonical course cover shape', () {
    final section = landingCourseSectionFromResponse({
      'items': [_canonicalCourse(cover: _canonicalCover)],
    });
    final card = section.items.single;

    expect(card.coverMediaId, '33333333-3333-3333-3333-333333333333');
    expect(card.cover?.resolvedUrl, 'https://cdn.test/cover.jpg');
  });

  test('landing course section accepts canonical null cover', () {
    final section = landingCourseSectionFromResponse({
      'items': [_canonicalCourse(cover: null)],
    });
    final card = section.items.single;

    expect(card.coverMediaId, '33333333-3333-3333-3333-333333333333');
    expect(card.cover, isNull);
  });

  test('landing course section rejects legacy resolved cover url shape', () {
    expect(
      () => landingCourseSectionFromResponse({
        'items': [
          {
            ..._canonicalCourse(cover: null),
            'resolved_cover_url': 'https://cdn.test/cover.jpg',
          },
        ],
      }),
      throwsStateError,
    );
  });

  test('landing course section rejects mixed legacy cover fields', () {
    expect(
      () => landingCourseSectionFromResponse({
        'items': [
          {
            ..._canonicalCourse(cover: null),
            'resolvedCoverUrl': 'https://cdn.test/cover.jpg',
          },
        ],
      }),
      throwsStateError,
    );
  });

  test('landing course section rejects non-canonical cover object fields', () {
    expect(
      () => landingCourseSectionFromResponse({
        'items': [
          _canonicalCourse(
            cover: {
              ..._canonicalCover,
              'playback_object_path': 'media/derived/cover/course.jpg',
            },
          ),
        ],
      }),
      throwsStateError,
    );
  });
}

const _canonicalCover = {
  'media_id': '33333333-3333-3333-3333-333333333333',
  'state': 'ready',
  'resolved_url': 'https://cdn.test/cover.jpg',
};

Map<String, Object?> _canonicalCourse({required Object? cover}) {
  return {
    'id': '11111111-1111-1111-1111-111111111111',
    'slug': 'course-one',
    'title': 'Kurs ett',
    'description': 'Backend landing description',
    'teacher': const {
      'user_id': '44444444-4444-4444-4444-444444444444',
      'display_name': 'Aveli Teacher',
    },
    'course_group_id': '22222222-2222-2222-2222-222222222222',
    'group_position': 1,
    'cover_media_id': '33333333-3333-3333-3333-333333333333',
    'cover': cover,
    'price_amount_cents': 9900,
    'drip_enabled': false,
    'drip_interval_days': null,
    'required_enrollment_source': 'purchase',
    'enrollable': false,
    'purchasable': true,
  };
}
