import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_journey_layout.dart';

void main() {
  group('buildCourseJourneySeriesRows', () {
    test('groups canonical course positions by course group id', () {
      final rows = buildCourseJourneySeriesRows([
        _course(
          id: 'intro',
          slug: 'intro',
          title: 'Intro',
          courseGroupId: 'intro-group',
          groupPosition: 0,
        ),
        _course(
          id: 'healing-1',
          slug: 'healing-1',
          title: 'Healing 1',
          courseGroupId: 'series:healing',
          groupPosition: 1,
        ),
        _course(
          id: 'healing-2',
          slug: 'healing-2',
          title: 'Healing 2',
          courseGroupId: 'series:healing',
          groupPosition: 2,
        ),
        _course(
          id: 'tarot-3',
          slug: 'tarot-3',
          title: 'Tarot 3',
          courseGroupId: 'series:tarot',
          groupPosition: 3,
        ),
      ]);

      expect(rows, hasLength(2));
      expect(rows[0].seriesKey, 'series:healing');
      expect(rows[0].step1?.id, 'healing-1');
      expect(rows[0].step2?.id, 'healing-2');
      expect(rows[0].step3, isNull);
      expect(rows[1].seriesKey, 'series:tarot');
      expect(rows[1].step1, isNull);
      expect(rows[1].step2, isNull);
      expect(rows[1].step3?.id, 'tarot-3');
    });

    test('keeps the first course for duplicate group positions', () {
      final rows = buildCourseJourneySeriesRows([
        _course(
          id: 'first',
          slug: 'first',
          title: 'First',
          courseGroupId: 'series:duplicate',
          groupPosition: 1,
        ),
        _course(
          id: 'second',
          slug: 'second',
          title: 'Second',
          courseGroupId: 'series:duplicate',
          groupPosition: 1,
        ),
      ]);

      expect(rows, hasLength(1));
      expect(rows.single.step1?.id, 'first');
    });
  });
}

CourseSummary _course({
  required String id,
  required String slug,
  required String title,
  required String courseGroupId,
  required int groupPosition,
}) {
  return CourseSummary(
    id: id,
    slug: slug,
    title: title,
    groupPosition: groupPosition,
    courseGroupId: courseGroupId,
    coverMediaId: null,
    cover: null,
    priceCents: null,
    dripEnabled: false,
    dripIntervalDays: null,
  );
}
