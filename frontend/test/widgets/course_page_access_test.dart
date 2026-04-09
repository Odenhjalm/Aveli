import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_page.dart';
import 'package:aveli/shared/utils/course_journey_step.dart';
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
  required CourseJourneyStep step,
}) {
  return CourseDetailData(
    course: CourseSummary(
      id: courseId,
      slug: slug,
      title: title,
      step: step,
      courseGroupId: 'group-1',
      coverMediaId: null,
      cover: null,
      priceCents: 0,
      dripEnabled: false,
      dripIntervalDays: null,
    ),
    lessons: const [
      LessonSummary(id: 'lesson-1', lessonTitle: 'Lesson 1', position: 1),
    ],
  );
}

CourseAccessData _enrolledState(String courseId) {
  return CourseAccessData(
    courseId: courseId,
    courseStep: CourseJourneyStep.intro,
    requiredEnrollmentSource: null,
    enrollment: CourseEnrollmentRecord(
      id: 'enrollment-1',
      userId: 'user-1',
      courseId: courseId,
      source: 'manual',
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
      step: CourseJourneyStep.intro,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              stripePublishableKey: 'pk_test',
              stripeMerchantDisplayName: 'Aveli Test',
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

  testWidgets('enrolled learners continue with unlocked lessons', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-enrolled',
      slug: 'enrolled-course',
      title: 'Enrolled Course',
      step: CourseJourneyStep.intro,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              stripePublishableKey: 'pk_test',
              stripeMerchantDisplayName: 'Aveli Test',
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
}
