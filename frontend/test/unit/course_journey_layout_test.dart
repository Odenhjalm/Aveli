import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_journey_layout.dart';
import 'package:aveli/shared/utils/course_journey_step.dart';

void main() {
  group('buildCourseJourneyRows', () {
    test(
      'keeps a missing later step empty before starting the next series',
      () {
        final rows = buildCourseJourneyRows([
          _course(
            id: 'healing-1',
            slug: 'healing-awakening',
            title: 'Healing Awakening',
            branch: 'Healing',
            step: CourseJourneyStep.step1,
          ),
          _course(
            id: 'healing-2',
            slug: 'healing-practice',
            title: 'Healing Practice',
            branch: 'Healing',
            step: CourseJourneyStep.step2,
          ),
          _course(
            id: 'tarot-1',
            slug: 'tarot-beginning',
            title: 'Tarot Beginning',
            branch: 'Tarot',
            step: CourseJourneyStep.step1,
          ),
          _course(
            id: 'tarot-2',
            slug: 'tarot-integration',
            title: 'Tarot Integration',
            branch: 'Tarot',
            step: CourseJourneyStep.step2,
          ),
          _course(
            id: 'tarot-3',
            slug: 'tarot-mastery',
            title: 'Tarot Mastery',
            branch: 'Tarot',
            step: CourseJourneyStep.step3,
          ),
        ]);

        expect(rows, hasLength(2));
        expect(rows[0].step1?.id, 'healing-1');
        expect(rows[0].step2?.id, 'healing-2');
        expect(rows[0].step3, isNull);
        expect(rows[1].step1?.id, 'tarot-1');
        expect(rows[1].step2?.id, 'tarot-2');
        expect(rows[1].step3?.id, 'tarot-3');
      },
    );

    test(
      'falls back to explicit step markers in slugs when branch is absent',
      () {
        final rows = buildCourseJourneyRows([
          _course(
            id: 'meditation-1',
            slug: 'meditation-step-1',
            title: 'Meditation Step 1',
            step: CourseJourneyStep.step1,
          ),
          _course(
            id: 'meditation-3',
            slug: 'meditation-step-3',
            title: 'Meditation Step 3',
            step: CourseJourneyStep.step3,
          ),
          _course(
            id: 'alchemy-1',
            slug: 'alchemy-step-1',
            title: 'Alchemy Step 1',
            step: CourseJourneyStep.step1,
          ),
        ]);

        expect(rows, hasLength(2));
        expect(rows[0].step1?.id, 'meditation-1');
        expect(rows[0].step2, isNull);
        expect(rows[0].step3?.id, 'meditation-3');
        expect(rows[1].step1?.id, 'alchemy-1');
        expect(rows[1].step2, isNull);
        expect(rows[1].step3, isNull);
      },
    );

    test(
      'creates additional rows when a series has multiple courses per step',
      () {
        final rows = buildCourseJourneyRows([
          _course(
            id: 'tarot-1a',
            slug: 'tarot-step-1',
            title: 'Tarot Steg 1',
            branch: 'Tarot',
            step: CourseJourneyStep.step1,
          ),
          _course(
            id: 'tarot-2a',
            slug: 'tarot-step-2',
            title: 'Tarot Steg 2',
            branch: 'Tarot',
            step: CourseJourneyStep.step2,
          ),
          _course(
            id: 'tarot-1b',
            slug: 'tarot-advanced-step-1',
            title: 'Tarot Avancerad Steg 1',
            branch: 'Tarot',
            step: CourseJourneyStep.step1,
          ),
          _course(
            id: 'tarot-2b',
            slug: 'tarot-advanced-step-2',
            title: 'Tarot Avancerad Steg 2',
            branch: 'Tarot',
            step: CourseJourneyStep.step2,
          ),
        ]);

        expect(rows, hasLength(2));
        expect(rows[0].step1?.id, 'tarot-1a');
        expect(rows[0].step2?.id, 'tarot-2a');
        expect(rows[1].step1?.id, 'tarot-1b');
        expect(rows[1].step2?.id, 'tarot-2b');
      },
    );
  });
}

CourseSummary _course({
  required String id,
  required String slug,
  required String title,
  required CourseJourneyStep step,
  String? branch,
}) {
  return CourseSummary(
    id: id,
    slug: slug,
    title: title,
    branch: branch,
    journeyStep: step,
  );
}
