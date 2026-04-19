import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/landing/application/landing_providers.dart';

void main() {
  test('landing course card parses canonical cover shape', () {
    final card = LandingCourseCard.fromResponse(const {
      'id': 'course-1',
      'slug': 'course-one',
      'title': 'Kurs ett',
      'group_position': 1,
      'cover_media_id': 'media-1',
      'cover': {
        'media_id': 'media-1',
        'state': 'ready',
        'resolved_url': 'https://cdn.test/cover.jpg',
      },
      'price_amount_cents': 9900,
      'short_description': 'Kort beskrivning',
    });

    expect(card.coverMediaId, 'media-1');
    expect(card.cover?.resolvedUrl, 'https://cdn.test/cover.jpg');
  });

  test('landing course card accepts canonical null cover', () {
    final card = LandingCourseCard.fromResponse(const {
      'id': 'course-1',
      'slug': 'course-one',
      'title': 'Kurs ett',
      'group_position': 1,
      'cover_media_id': 'media-1',
      'cover': null,
      'price_amount_cents': 9900,
      'short_description': null,
    });

    expect(card.coverMediaId, 'media-1');
    expect(card.cover, isNull);
  });

  test('landing course card rejects legacy resolved cover url shape', () {
    expect(
      () => LandingCourseCard.fromResponse(const {
        'id': 'course-1',
        'slug': 'course-one',
        'title': 'Kurs ett',
        'group_position': 1,
        'resolved_cover_url': 'https://cdn.test/cover.jpg',
        'price_amount_cents': 9900,
        'short_description': null,
      }),
      throwsStateError,
    );
  });
}
