import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_page.dart';
import 'package:aveli/shared/utils/course_cover_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _TestAuthController extends AuthController {
  _TestAuthController({
    required AuthRepository repo,
    required AuthHttpObserver observer,
    Profile? profile,
  }) : super(repo, observer) {
    state = AuthState(profile: profile, isLoading: false);
  }
}

CourseDetailData _detail({
  required String courseId,
  required String slug,
  required String title,
  required int groupPosition,
  String? coverMediaId,
  CourseCoverData? cover,
  int? priceCents = 0,
  bool? enrollable,
  bool? purchasable,
  String? shortDescription = 'Backendbeskriven kurs för startklara elever.',
}) {
  final isFreeIntro =
      groupPosition == 0 && (priceCents == null || priceCents == 0);
  return CourseDetailData(
    course: CourseSummary(
      id: courseId,
      slug: slug,
      title: title,
      teacher: const CourseTeacherData(
        userId: 'teacher-1',
        displayName: 'Aveli Teacher',
      ),
      groupPosition: groupPosition,
      courseGroupId: 'group-1',
      coverMediaId: coverMediaId,
      cover: cover,
      priceCents: priceCents,
      dripEnabled: false,
      dripIntervalDays: null,
      requiredEnrollmentSource: (enrollable ?? isFreeIntro)
          ? 'intro_enrollment'
          : 'purchase',
      enrollable: enrollable ?? isFreeIntro,
      purchasable: purchasable ?? !isFreeIntro,
    ),
    lessons: const [
      LessonSummary(id: 'lesson-1', lessonTitle: 'Lesson 1', position: 1),
    ],
    shortDescription: shortDescription,
  );
}

CourseAccessData _enrolledState(String courseId) {
  return CourseAccessData(
    courseId: courseId,
    groupPosition: 0,
    requiredEnrollmentSource: 'intro_enrollment',
    enrollable: true,
    purchasable: false,
    enrollment: CourseEnrollmentRecord(
      id: 'enrollment-1',
      userId: 'user-1',
      courseId: courseId,
      source: 'intro_enrollment',
      grantedAt: DateTime.utc(2024, 1, 1),
      dripStartedAt: DateTime.utc(2024, 1, 1),
      currentUnlockPosition: 1,
    ),
  );
}

void main() {
  Override authOverride({Profile? profile}) {
    final repo = _MockAuthRepository();
    final observer = AuthHttpObserver();
    return authControllerProvider.overrideWith(
      (ref) =>
          _TestAuthController(repo: repo, observer: observer, profile: profile),
    );
  }

  testWidgets('intro courses show the canonical enrollment CTA', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-intro',
      slug: 'intro-course',
      title: 'Intro Course',
      groupPosition: 2,
      enrollable: true,
      purchasable: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith((ref, courseId) async => null),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'intro-course')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Starta introduktion'), findsOneWidget);
  });

  testWidgets('course detail renders backend teacher and description', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-detail',
      slug: 'detail-course',
      title: 'Detail Course',
      groupPosition: 0,
      shortDescription: 'En tydlig kursbeskrivning från backend.',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith((ref, courseId) async => null),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'detail-course')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Lärare: Aveli Teacher'), findsOneWidget);
    expect(
      find.text('En tydlig kursbeskrivning från backend.'),
      findsOneWidget,
    );
  });

  testWidgets('sellable position-zero courses do not show enrollment CTA', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-paid-zero',
      slug: 'paid-zero-course',
      title: 'Paid Zero Course',
      groupPosition: 0,
      priceCents: 9900,
      enrollable: false,
      purchasable: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith((ref, courseId) async => null),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'paid-zero-course')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Starta introduktion'), findsNothing);
  });

  testWidgets('enrolled learners continue with unlocked lessons', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-enrolled',
      slug: 'enrolled-course',
      title: 'Enrolled Course',
      groupPosition: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith(
            (ref, courseId) async => _enrolledState(courseId),
          ),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'enrolled-course')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Forts'), findsOneWidget);
    expect(find.text('Lesson 1'), findsOneWidget);
  });

  testWidgets('learner course page renders backend cover resolved url', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-cover',
      slug: 'cover-course',
      title: 'Cover Course',
      groupPosition: 0,
      coverMediaId: 'media-1',
      cover: const CourseCoverData(
        mediaId: 'media-1',
        state: 'ready',
        resolvedUrl: 'https://cdn.test/course-cover.jpg',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith((ref, courseId) async => null),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'cover-course')),
      ),
    );

    await tester.pump();
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

  testWidgets('paid course page renders cover without enrollment state', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-paid-cover',
      slug: 'paid-cover-course',
      title: 'Paid Cover Course',
      groupPosition: 1,
      priceCents: 9900,
      coverMediaId: 'media-1',
      cover: const CourseCoverData(
        mediaId: 'media-1',
        state: 'ready',
        resolvedUrl: 'https://cdn.test/paid-course-cover.jpg',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith((ref, courseId) async => null),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'paid-cover-course')),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url ==
                'https://cdn.test/paid-course-cover.jpg',
        description: 'Image.network(https://cdn.test/paid-course-cover.jpg)',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isA<NetworkImageLoadException>());
  });
}
