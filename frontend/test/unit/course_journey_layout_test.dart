import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_journey_layout.dart';
import 'package:aveli/shared/utils/course_journey_step.dart';

void main() {
  group('buildCourseJourneySeriesRows', () {
    test(
      'keeps a missing later step empty before starting the next series',
      () {
        final rows = buildCourseJourneySeriesRows([
          _course(
            id: 'healing-1',
            slug: 'healing-awakening',
            title: 'Healing Awakening',
            courseFamily: 'healing-awakening',
            step: CourseJourneyStep.step1,
          ),
          _course(
            id: 'healing-2',
            slug: 'healing-practice',
            title: 'Healing Practice',
            courseFamily: 'healing-awakening',
            step: CourseJourneyStep.step2,
          ),
          _course(
            id: 'tarot-1',
            slug: 'tarot-beginning',
            title: 'Tarot Beginning',
            courseFamily: 'tarot-beginning',
            step: CourseJourneyStep.step1,
          ),
          _course(
            id: 'tarot-2',
            slug: 'tarot-integration',
            title: 'Tarot Integration',
            courseFamily: 'tarot-beginning',
            step: CourseJourneyStep.step2,
          ),
          _course(
            id: 'tarot-3',
            slug: 'tarot-mastery',
            title: 'Tarot Mastery',
            courseFamily: 'tarot-beginning',
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
        final rows = buildCourseJourneySeriesRows([
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
      'uses course family before branch so separate journeys do not interleave',
      () {
        final rows = buildCourseJourneySeriesRows([
          _course(
            id: 'tarot-core-1',
            slug: 'tarot-core-step-1',
            title: 'Tarot Core Steg 1',
            branch: 'Tarot',
            courseFamily: 'tarot-core',
            step: CourseJourneyStep.step1,
          ),
          _course(
            id: 'tarot-advanced-1',
            slug: 'tarot-advanced-step-1',
            title: 'Tarot Advanced Steg 1',
            branch: 'Tarot',
            courseFamily: 'tarot-advanced',
            step: CourseJourneyStep.step1,
          ),
          _course(
            id: 'tarot-core-2',
            slug: 'tarot-core-step-2',
            title: 'Tarot Core Steg 2',
            branch: 'Tarot',
            courseFamily: 'tarot-core',
            step: CourseJourneyStep.step2,
          ),
          _course(
            id: 'tarot-advanced-2',
            slug: 'tarot-advanced-step-2',
            title: 'Tarot Advanced Steg 2',
            branch: 'Tarot',
            courseFamily: 'tarot-advanced',
            step: CourseJourneyStep.step2,
          ),
        ]);

        expect(rows, hasLength(2));
        expect(rows[0].seriesKey, 'series:tarot-core');
        expect(rows[0].step1?.id, 'tarot-core-1');
        expect(rows[0].step2?.id, 'tarot-core-2');
        expect(rows[0].step3, isNull);
        expect(rows[1].seriesKey, 'series:tarot-advanced');
        expect(rows[1].step1?.id, 'tarot-advanced-1');
        expect(rows[1].step2?.id, 'tarot-advanced-2');
        expect(rows[1].step3, isNull);
      },
    );

    test(
      'normalizes step-suffixed course family values into one dedicated row',
      () {
        final rows = buildCourseJourneySeriesRows([
          _course(
            id: 'healing-1',
            slug: 'healing-path-step-1',
            title: 'Healing Path Steg 1',
            courseFamily: 'healing-path-step-1',
            step: CourseJourneyStep.step1,
          ),
          _course(
            id: 'healing-2',
            slug: 'healing-path-step-2',
            title: 'Healing Path Steg 2',
            courseFamily: 'healing-path-step-2',
            step: CourseJourneyStep.step2,
          ),
        ]);

        expect(rows, hasLength(1));
        expect(rows[0].seriesKey, 'series:healing-path');
        expect(rows[0].step1?.id, 'healing-1');
        expect(rows[0].step2?.id, 'healing-2');
        expect(rows[0].step3, isNull);
      },
    );

    test(
      'groups real del-series titles even when the step marker has trailing text or slug noise',
      () {
        final rows = buildCourseJourneySeriesRows([
          _course(
            id: 'herbs-1',
            slug: 'utbildning-sjalvlakande-orter-och-nutrition-ax8b-hfrn5g87js',
            title: 'Utbildning Självläkande örter & nutrition del 1',
            step: CourseJourneyStep.step1,
          ),
          _course(
            id: 'herbs-2',
            slug:
                'utbildning-sjalvlakande-orter-och-nutrition-del-2-1v3d-hfrncjb1c8',
            title: 'Utbildning Självläkande örter & nutrition del 2',
            step: CourseJourneyStep.step2,
          ),
          _course(
            id: 'meditation-3',
            slug:
                'utbildning-spirituell-meditation-del-3-l460-hfrms0fis0',
            title:
                'Utbildning Spirituell meditation del 3 Meditationscoach',
            step: CourseJourneyStep.step3,
          ),
          _course(
            id: 'meditation-2',
            slug:
                'utbildning-spirituell-meditation-del-2-1274-hfrmnf8wug',
            title: 'Utbildning Spirituell meditation del 2',
            step: CourseJourneyStep.step2,
          ),
          _course(
            id: 'meditation-1',
            slug:
                'utbildning-spirituell-meditation-del-1-8m5g-hfrmdjn6yo',
            title: 'Utbildning Spirituell Meditation del 1',
            step: CourseJourneyStep.step1,
          ),
        ]);

        expect(rows, hasLength(2));
        expect(rows[0].step1?.id, 'herbs-1');
        expect(rows[0].step2?.id, 'herbs-2');
        expect(rows[0].step3, isNull);
        expect(rows[1].step1?.id, 'meditation-1');
        expect(rows[1].step2?.id, 'meditation-2');
        expect(rows[1].step3?.id, 'meditation-3');
      },
    );

    test(
      'matches one series even when one step only derives its root from title and another from slug',
      () {
        final rows = buildCourseJourneySeriesRows([
          _course(
            id: 'coach-1',
            slug: 'legacy-coach-slug',
            title: 'Utbildning - Spirituell coach del 1',
            step: CourseJourneyStep.step1,
          ),
          _course(
            id: 'coach-2',
            slug: 'utbildning-spirituell-coach-del-2-9on6-hfraa543ls',
            title: 'Fördjupning för coacher',
            step: CourseJourneyStep.step2,
          ),
          _course(
            id: 'coach-3',
            slug: 'utbildning-spirituell-coach-del-3-d44j-hfradfx7oo',
            title: 'Utbildning Spirituell coach del 3',
            step: CourseJourneyStep.step3,
          ),
        ]);

        expect(rows, hasLength(1));
        expect(rows[0].step1?.id, 'coach-1');
        expect(rows[0].step2?.id, 'coach-2');
        expect(rows[0].step3?.id, 'coach-3');
      },
    );

    test(
      'keeps a series to a single fixed row even if a duplicate step is present',
      () {
        final rows = buildCourseJourneySeriesRows([
          _course(
            id: 'duplicate-1a',
            slug: 'duplicate-step-1-a',
            title: 'Duplicate Steg 1 A',
            courseFamily: 'duplicate-series',
            step: CourseJourneyStep.step1,
          ),
          _course(
            id: 'duplicate-1b',
            slug: 'duplicate-step-1-b',
            title: 'Duplicate Steg 1 B',
            courseFamily: 'duplicate-series',
            step: CourseJourneyStep.step1,
          ),
          _course(
            id: 'duplicate-2',
            slug: 'duplicate-step-2',
            title: 'Duplicate Steg 2',
            courseFamily: 'duplicate-series',
            step: CourseJourneyStep.step2,
          ),
        ]);

        expect(rows, hasLength(1));
        expect(rows[0].step1?.id, 'duplicate-1a');
        expect(rows[0].step2?.id, 'duplicate-2');
        expect(rows[0].step3, isNull);
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
  String? courseFamily,
}) {
  return CourseSummary(
    id: id,
    slug: slug,
    title: title,
    branch: branch,
    courseFamily: courseFamily,
    journeyStep: step,
  );
}
