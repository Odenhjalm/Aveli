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
          (ref) async =>
              const landing.LandingSection<landing.LandingCourseCard>(
                items: [],
              ),
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
        _course(id: 'step-2', title: 'Zen Flow', groupPosition: 2),
        _course(id: 'step-1-b', title: 'Breathwork', groupPosition: 1),
        _course(id: 'intro-b', title: 'Aurora', groupPosition: 0),
        _course(id: 'step-3', title: 'Tarot Mastery', groupPosition: 3),
        _course(id: 'unknown', title: 'Mystery Course'),
        _course(id: 'intro-a', title: 'Alchemy Basics', groupPosition: 0),
        _course(id: 'step-1-a', title: 'Astral Travel', groupPosition: 1),
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

CourseSummary _course({
  required String id,
  required String title,
  int groupPosition = 4,
}) {
  return CourseSummary(
    id: id,
    slug: 'foundations-of-soulwisdom',
    title: title,
    groupPosition: groupPosition,
    courseGroupId: 'series:foundations-of-soulwisdom',
    coverMediaId: null,
    cover: null,
    priceCents: null,
    dripEnabled: false,
    dripIntervalDays: null,
  );
}
