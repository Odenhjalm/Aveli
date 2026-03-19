import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import 'package:aveli/shared/utils/course_journey_step.dart';
import 'package:aveli/shared/widgets/courses_showcase_section.dart';

import '../helpers/backend_asset_resolver_stub.dart';

class _MockMediaRepository extends Mock implements MediaRepository {}

Future<void> _pumpShowcase(
  WidgetTester tester, {
  required List<CourseSummary> courses,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendAssetResolverProvider.overrideWith(
          (ref) => TestBackendAssetResolver(),
        ),
        mediaRepositoryProvider.overrideWithValue(_MockMediaRepository()),
        landing.popularCoursesProvider.overrideWith(
          (ref) async => const landing.LandingSectionState(items: []),
        ),
        coursesProvider.overrideWith((ref) => Future.value(courses)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 580,
              child: CoursesShowcaseSection(
                title: 'Utforska kurser',
                includeOuterChrome: false,
                includeStudioCourses: false,
                showHeroBadge: false,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

Offset _titlePosition(WidgetTester tester, String title) {
  return tester.getTopLeft(find.text(title));
}

void main() {
  testWidgets(
    'showcase renders intro to step3 order with alphabetical titles',
    (tester) async {
      final courses = <CourseSummary>[
        const CourseSummary(
          id: 'step-2',
          slug: 'foundations-of-soulwisdom',
          title: 'Zen Flow',
          journeyStep: CourseJourneyStep.step2,
        ),
        const CourseSummary(
          id: 'step-1-b',
          slug: 'foundations-of-soulwisdom',
          title: 'Breathwork',
          journeyStep: CourseJourneyStep.step1,
        ),
        const CourseSummary(
          id: 'intro-b',
          slug: 'foundations-of-soulwisdom',
          title: 'Aurora',
          journeyStep: CourseJourneyStep.intro,
        ),
        const CourseSummary(
          id: 'step-3',
          slug: 'foundations-of-soulwisdom',
          title: 'Tarot Mastery',
          journeyStep: CourseJourneyStep.step3,
        ),
        const CourseSummary(
          id: 'unknown',
          slug: 'foundations-of-soulwisdom',
          title: 'Mystery Course',
        ),
        const CourseSummary(
          id: 'intro-a',
          slug: 'foundations-of-soulwisdom',
          title: 'Alchemy Basics',
          journeyStep: CourseJourneyStep.intro,
        ),
        const CourseSummary(
          id: 'step-1-a',
          slug: 'foundations-of-soulwisdom',
          title: 'Astral Travel',
          journeyStep: CourseJourneyStep.step1,
        ),
      ];

      await _pumpShowcase(tester, courses: courses);

      final expectedTitles = <String>[
        'Alchemy Basics',
        'Aurora',
        'Astral Travel',
        'Breathwork',
        'Zen Flow',
        'Tarot Mastery',
        'Mystery Course',
      ];

      for (final title in expectedTitles) {
        expect(find.text(title), findsOneWidget);
      }

      var previous = _titlePosition(tester, expectedTitles.first);
      for (final title in expectedTitles.skip(1)) {
        final current = _titlePosition(tester, title);
        expect(current.dy, greaterThan(previous.dy));
        previous = current;
      }

      await _pumpShowcase(tester, courses: courses);

      previous = _titlePosition(tester, expectedTitles.first);
      for (final title in expectedTitles.skip(1)) {
        final current = _titlePosition(tester, title);
        expect(current.dy, greaterThan(previous.dy));
        previous = current;
      }
    },
  );
}
