import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_journey_layout.dart';

void main() {
  group('buildCourseJourneyFamilies', () {
    test('keeps a single course as an intro-only family', () {
      final families = buildCourseJourneyFamilies([
        _course(
          id: 'intro',
          slug: 'intro',
          title: 'Intro',
          courseGroupId: 'series:solo',
          groupPosition: 0,
          requiredEnrollmentSource: 'intro',
          enrollable: true,
          purchasable: false,
        ),
      ]);

      expect(families, hasLength(1));
      expect(families.single.courseGroupId, 'series:solo');
      expect(families.single.introCourse?.id, 'intro');
      expect(families.single.progressionCourses, isEmpty);
    });

    test('sorts each family strictly by canonical group_position', () {
      final families = buildCourseJourneyFamilies([
        _course(
          id: 'healing-3',
          slug: 'healing-3',
          title: 'Healing 3',
          courseGroupId: 'series:healing',
          groupPosition: 3,
        ),
        _course(
          id: 'healing-1',
          slug: 'healing-1',
          title: 'Healing 1',
          courseGroupId: 'series:healing',
          groupPosition: 1,
        ),
        _course(
          id: 'healing-intro',
          slug: 'healing-intro',
          title: 'Healing Intro',
          courseGroupId: 'series:healing',
          groupPosition: 0,
          requiredEnrollmentSource: 'intro',
          enrollable: true,
          purchasable: false,
        ),
        _course(
          id: 'healing-2',
          slug: 'healing-2',
          title: 'Healing 2',
          courseGroupId: 'series:healing',
          groupPosition: 2,
        ),
        _course(
          id: 'tarot-intro',
          slug: 'tarot-intro',
          title: 'Tarot Intro',
          courseGroupId: 'series:tarot',
          groupPosition: 0,
          requiredEnrollmentSource: 'intro',
          enrollable: true,
          purchasable: false,
        ),
        _course(
          id: 'tarot-1',
          slug: 'tarot-1',
          title: 'Tarot 1',
          courseGroupId: 'series:tarot',
          groupPosition: 1,
        ),
      ]);

      expect(families, hasLength(2));
      expect(families[0].courseGroupId, 'series:healing');
      expect(families[0].introCourse?.id, 'healing-intro');
      expect(
        families[0].progressionCourses.map((course) => course.id).toList(),
        ['healing-1', 'healing-2', 'healing-3'],
      );
      expect(families[1].courseGroupId, 'series:tarot');
      expect(families[1].introCourse?.id, 'tarot-intro');
      expect(
        families[1].progressionCourses.map((course) => course.id).toList(),
        ['tarot-1'],
      );
    });

    test(
      'drops invalid duplicate or sparse families instead of canonizing them',
      () {
        final families = buildCourseJourneyFamilies([
          _course(
            id: 'duplicate-intro',
            slug: 'duplicate-intro',
            title: 'Duplicate Intro',
            courseGroupId: 'series:duplicate',
            groupPosition: 0,
            requiredEnrollmentSource: 'intro',
            enrollable: true,
            purchasable: false,
          ),
          _course(
            id: 'duplicate-progress-a',
            slug: 'duplicate-progress-a',
            title: 'Duplicate A',
            courseGroupId: 'series:duplicate',
            groupPosition: 1,
          ),
          _course(
            id: 'duplicate-progress-b',
            slug: 'duplicate-progress-b',
            title: 'Duplicate B',
            courseGroupId: 'series:duplicate',
            groupPosition: 1,
          ),
          _course(
            id: 'sparse-intro',
            slug: 'sparse-intro',
            title: 'Sparse Intro',
            courseGroupId: 'series:sparse',
            groupPosition: 0,
            requiredEnrollmentSource: 'intro',
            enrollable: true,
            purchasable: false,
          ),
          _course(
            id: 'sparse-progress',
            slug: 'sparse-progress',
            title: 'Sparse Progress',
            courseGroupId: 'series:sparse',
            groupPosition: 2,
          ),
        ]);

        expect(families, isEmpty);
      },
    );
  });
}

CourseSummary _course({
  required String id,
  required String slug,
  required String title,
  required String courseGroupId,
  required int groupPosition,
  String requiredEnrollmentSource = 'purchase',
  bool enrollable = false,
  bool purchasable = true,
}) {
  return CourseSummary(
    id: id,
    slug: slug,
    title: title,
    description: 'Backend unit description',
    teacher: const CourseTeacherData(
      userId: 'teacher-1',
      displayName: 'Aveli Teacher',
    ),
    groupPosition: groupPosition,
    courseGroupId: courseGroupId,
    coverMediaId: null,
    cover: null,
    priceCents: null,
    dripEnabled: false,
    dripIntervalDays: null,
    requiredEnrollmentSource: requiredEnrollmentSource,
    enrollable: enrollable,
    purchasable: purchasable,
  );
}
