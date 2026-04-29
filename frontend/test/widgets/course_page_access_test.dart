import 'dart:async';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_page.dart';
import 'package:aveli/shared/data/app_render_inputs_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('Course Page renders from entry-view CTA and course fields', (
    tester,
  ) async {
    await _pumpCoursePage(
      tester,
      _entryView(
        title: 'Intro Course',
        description: 'Backend-authored intro description',
        cta: const CourseEntryCtaData(
          type: 'enroll',
          label: 'Starta introduktion',
          enabled: true,
          reasonCode: null,
          reasonText: null,
          price: null,
          action: {'type': 'enroll'},
        ),
      ),
    );

    expect(find.text('Intro Course'), findsWidgets);
    expect(find.text('Backend-authored intro description'), findsOneWidget);
    expect(find.text('Starta introduktion'), findsOneWidget);
    expect(find.text('Lesson 1'), findsOneWidget);
    expect(find.text('current'), findsOneWidget);
  });

  testWidgets('blocked intro CTA renders backend reason and disabled state', (
    tester,
  ) async {
    await _pumpCoursePage(
      tester,
      _entryView(
        access: const CourseEntryAccessData(
          isEnrolled: false,
          isInDrip: false,
          isInAnyIntroDrip: true,
          enrollAllowed: false,
          purchaseAllowed: false,
        ),
        cta: const CourseEntryCtaData(
          type: 'blocked',
          label: 'Blocked',
          enabled: false,
          reasonCode: 'active_intro_drip',
          reasonText:
              'Finish your active intro course before starting another.',
          price: null,
          action: null,
        ),
      ),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('Blocked'), findsOneWidget);
    expect(
      find.text('Finish your active intro course before starting another.'),
      findsOneWidget,
    );
  });

  testWidgets('premium course shows backend formatted price and buy CTA', (
    tester,
  ) async {
    await _pumpCoursePage(
      tester,
      _entryView(
        requiredEnrollmentSource: 'purchase',
        premium: true,
        pricing: const CourseEntryPricingData(
          priceAmountCents: 99000,
          priceCurrency: 'sek',
          formattedPrice: '990 kr',
          sellable: true,
        ),
        cta: const CourseEntryCtaData(
          type: 'buy',
          label: 'K\u00f6p kursen',
          enabled: true,
          reasonCode: null,
          reasonText: null,
          price: {
            'price_amount_cents': 99000,
            'price_currency': 'sek',
            'formatted_price': '990 kr',
            'sellable': true,
          },
          action: {'type': 'checkout'},
        ),
      ),
    );

    expect(find.text('990 kr'), findsOneWidget);
    expect(find.text('K\u00f6p kursen'), findsOneWidget);
  });

  testWidgets('locked lessons render backend availability without local math', (
    tester,
  ) async {
    await _pumpCoursePage(
      tester,
      _entryView(
        lessons: [
          _lesson(
            id: 'lesson-1',
            title: 'Lesson 1',
            availability: const CourseEntryLessonAvailabilityData(
              state: 'unlocked',
              canOpen: true,
              reasonCode: null,
              reasonText: null,
              nextUnlockAt: null,
            ),
            progression: const CourseEntryLessonProgressionData(
              state: 'completed',
              completedAt: null,
              isNextRecommended: false,
            ),
          ),
          _lesson(
            id: 'lesson-2',
            title: 'Lesson 2',
            availability: const CourseEntryLessonAvailabilityData(
              state: 'locked',
              canOpen: false,
              reasonCode: 'drip_locked',
              reasonText: 'Available later',
              nextUnlockAt: null,
            ),
            progression: const CourseEntryLessonProgressionData(
              state: 'upcoming',
              completedAt: null,
              isNextRecommended: false,
            ),
          ),
        ],
      ),
    );

    expect(find.text('Lesson 1'), findsOneWidget);
    expect(find.text('completed'), findsOneWidget);
    expect(find.text('Lesson 2'), findsOneWidget);
    expect(find.text('Available later'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
  });

  testWidgets('Course Page renders entry-view cover URL', (tester) async {
    await _pumpCoursePage(
      tester,
      _entryView(
        cover: const CourseEntryCoverData(
          url: 'https://cdn.test/course-cover.jpg',
          alt: 'Course cover',
        ),
      ),
    );

    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url ==
                'https://cdn.test/course-cover.jpg',
        description: 'Image.network(https://cdn.test/course-cover.jpg)',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isA<NetworkImageLoadException>());
  });

  testWidgets('Course Page load error hides raw backend or parser text', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._scaffoldOverrides(),
          courseEntryViewProvider.overrideWith(
            (ref, slug) async =>
                throw StateError('Course not found: backend internal text'),
          ),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'missing-course')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Kursen kunde inte laddas.'), findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.textContaining('Course not found'), findsNothing);
    expect(find.textContaining('backend internal'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpCoursePage(
  WidgetTester tester,
  CourseEntryViewData view,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._scaffoldOverrides(),
        courseEntryViewProvider.overrideWith((ref, slug) async => view),
      ],
      child: const MaterialApp(home: CoursePage(slug: 'intro-course')),
    ),
  );
  await tester.pumpAndSettle();
}

List<Override> _scaffoldOverrides() {
  return [
    appConfigProvider.overrideWithValue(
      const AppConfig(
        apiBaseUrl: 'http://localhost:8080',
        subscriptionsEnabled: true,
      ),
    ),
    brandLogoRenderInputProvider.overrideWith((ref) => _pendingLogo),
    uiBackgroundRenderInputProvider.overrideWith(
      (ref, key) => _pendingBackground,
    ),
  ];
}

final _pendingLogo = Completer<BrandLogoRenderInput>().future;
final _pendingBackground = Completer<UiBackgroundRenderInput>().future;

CourseEntryViewData _entryView({
  String title = 'Course Title',
  String? description = 'Backend-authored description',
  String? requiredEnrollmentSource = 'intro',
  bool premium = false,
  CourseEntryCoverData? cover,
  CourseEntryAccessData access = const CourseEntryAccessData(
    isEnrolled: true,
    isInDrip: false,
    isInAnyIntroDrip: false,
    enrollAllowed: false,
    purchaseAllowed: false,
  ),
  CourseEntryCtaData cta = const CourseEntryCtaData(
    type: 'continue',
    label: 'Continue',
    enabled: true,
    reasonCode: null,
    reasonText: null,
    price: null,
    action: {'type': 'lesson', 'lesson_id': 'lesson-1'},
  ),
  CourseEntryPricingData? pricing,
  List<CourseEntryLessonShellData>? lessons,
  CourseEntryNextRecommendedLessonData? nextRecommendedLesson =
      const CourseEntryNextRecommendedLessonData(
        id: 'lesson-1',
        lessonTitle: 'Lesson 1',
        position: 1,
      ),
}) {
  return CourseEntryViewData(
    course: CourseEntryCourseData(
      id: 'course-1',
      slug: 'intro-course',
      title: title,
      description: description,
      cover: cover,
      requiredEnrollmentSource: requiredEnrollmentSource,
      premium: premium,
      priceAmountCents: pricing?.priceAmountCents,
      priceCurrency: pricing?.priceCurrency,
      formattedPrice: pricing?.formattedPrice,
      sellable: pricing?.sellable ?? false,
    ),
    lessons: lessons ?? [_lesson()],
    access: access,
    cta: cta,
    pricing: pricing,
    nextRecommendedLesson: nextRecommendedLesson,
  );
}

CourseEntryLessonShellData _lesson({
  String id = 'lesson-1',
  String title = 'Lesson 1',
  int position = 1,
  CourseEntryLessonAvailabilityData availability =
      const CourseEntryLessonAvailabilityData(
        state: 'unlocked',
        canOpen: true,
        reasonCode: null,
        reasonText: null,
        nextUnlockAt: null,
      ),
  CourseEntryLessonProgressionData progression =
      const CourseEntryLessonProgressionData(
        state: 'current',
        completedAt: null,
        isNextRecommended: true,
      ),
}) {
  return CourseEntryLessonShellData(
    id: id,
    lessonTitle: title,
    position: position,
    availability: availability,
    progression: progression,
  );
}
