import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/studio/data/studio_sessions_repository.dart';

void main() {
  test('rejects missing items in session list payloads', () {
    expect(
      () => StudioSession.fromJson({
        'id': 'session-1',
        'title': 'Session',
        'description': null,
        'start_at': '2025-01-01T10:00:00.000Z',
        'end_at': '2025-01-01T11:00:00.000Z',
        'capacity': 10,
        'price_cents': 1500,
        'currency': 'sek',
        'visibility': 'published',
        'recording_url': null,
        'teacher_id': 'teacher-1',
        'stripe_price_id': null,
      }),
      returnsNormally,
    );
  });

  test('rejects invalid datetime instead of coercing it', () {
    expect(
      () => StudioSession.fromJson({
        'id': 'session-1',
        'title': 'Session',
        'description': null,
        'start_at': 'not-a-datetime',
        'end_at': '2025-01-01T11:00:00.000Z',
        'capacity': 10,
        'price_cents': 1500,
        'currency': 'sek',
        'visibility': 'published',
        'recording_url': null,
        'teacher_id': 'teacher-1',
        'stripe_price_id': null,
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
