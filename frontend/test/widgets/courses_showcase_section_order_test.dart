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
import 'package:aveli/shared/utils/course_cover_contract.dart';
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
          (ref) async => const landing.LandingSection<CourseSummary>(items: []),
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
    'showcase renders canonical group_position order with alphabetical titles',
    (tester) async {
      final courses = <CourseSummary>[
        _course(id: 'step-2', title: 'Zen Flow', groupPosition: 2),
        _course(id: 'step-1-b', title: 'Breathwork', groupPosition: 1),
        _course(
          id: 'intro-b',
          title: 'Aurora',
          groupPosition: 0,
          requiredEnrollmentSource: 'intro_enrollment',
          enrollable: true,
          purchasable: false,
        ),
        _course(id: 'step-3', title: 'Tarot Mastery', groupPosition: 3),
        _course(id: 'step-4', title: 'Celestial Practice', groupPosition: 4),
        _course(id: 'unknown', title: 'Mystery Course'),
        _course(
          id: 'intro-a',
          title: 'Alchemy Basics',
          groupPosition: 0,
          requiredEnrollmentSource: 'intro_enrollment',
          enrollable: true,
          purchasable: false,
        ),
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
        'Celestial Practice',
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

  testWidgets('showcase renders premium course cover without purchase state', (
    tester,
  ) async {
    final courses = <CourseSummary>[
      _course(
        id: 'premium-cover',
        title: 'Premium Cover',
        groupPosition: 1,
        coverMediaId: 'media-1',
        cover: const CourseCoverData(
          mediaId: 'media-1',
          state: 'ready',
          resolvedUrl: 'https://cdn.test/showcase-premium-cover.jpg',
        ),
        priceCents: 9900,
      ),
    ];

    await _pumpShowcase(tester, courses: courses);
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url ==
                'https://cdn.test/showcase-premium-cover.jpg',
        description:
            'Image.network(https://cdn.test/showcase-premium-cover.jpg)',
      ),
      findsOneWidget,
    );
    final exception = tester.takeException();
    if (exception != null) {
      expect(exception, isA<NetworkImageLoadException>());
    }
  });
}

CourseSummary _course({
  required String id,
  required String title,
  int groupPosition = 4,
  String? coverMediaId,
  CourseCoverData? cover,
  int? priceCents,
  String requiredEnrollmentSource = 'purchase',
  bool enrollable = false,
  bool purchasable = true,
}) {
  return CourseSummary(
    id: id,
    slug: 'foundations-of-soulwisdom',
    title: title,
    teacher: const CourseTeacherData(
      userId: 'teacher-1',
      displayName: 'Aveli Teacher',
    ),
    groupPosition: groupPosition,
    courseGroupId: 'series:foundations-of-soulwisdom',
    coverMediaId: coverMediaId,
    cover: cover,
    priceCents: priceCents,
    dripEnabled: false,
    dripIntervalDays: null,
    requiredEnrollmentSource: requiredEnrollmentSource,
    enrollable: enrollable,
    purchasable: purchasable,
  );
}
