import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_page.dart';
import 'package:aveli/features/paywall/application/pricing_providers.dart';
import 'package:aveli/features/paywall/data/course_pricing_api.dart';
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
    state = AuthState(profile: profile, claims: null, isLoading: false);
  }
}

void main() {
  final ownerProfile = Profile(
    id: 'owner-1',
    email: 'owner@example.com',
    userRole: UserRole.teacher,
    isAdmin: false,
    createdAt: DateTime.utc(2024, 1, 1),
    updatedAt: DateTime.utc(2024, 1, 1),
  );

  Override authOverride({Profile? profile}) {
    final repo = _MockAuthRepository();
    final observer = AuthHttpObserver();
    return authControllerProvider.overrideWith(
      (ref) =>
          _TestAuthController(repo: repo, observer: observer, profile: profile),
    );
  }

  testWidgets(
    'teacher access keeps paid lessons unlocked without intro quota UI',
    (tester) async {
      final detail = CourseDetailData(
        course: const CourseSummary(
          id: 'course-1',
          slug: 'paid-course',
          title: 'Paid Course',
          description: 'Teacher owned',
          isFreeIntro: false,
          isPublished: false,
          priceCents: 12900,
        ),
        modules: const [
          CourseModule(
            id: 'course-1',
            courseId: 'course-1',
            title: 'Lektioner',
            position: 0,
          ),
        ],
        lessonsByModule: const {
          'course-1': [
            LessonSummary(
              id: 'lesson-1',
              title: 'Premium Lesson',
              position: 1,
              isIntro: false,
            ),
          ],
        },
        hasAccess: true,
        accessReason: 'teacher',
        isEnrolled: false,
        hasActiveSubscription: false,
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
            coursePricingProvider.overrideWith(
              (ref, slug) async =>
                  CoursePricing(amountCents: 12900, currency: 'sek'),
            ),
          ],
          child: const MaterialApp(home: CoursePage(slug: 'paid-course')),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Läraråtkomst'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
      expect(find.textContaining('Använda introduktioner'), findsNothing);
    },
  );

  testWidgets('test_owner_sees_all_lessons_and_no_intro_cta', (tester) async {
    final detail = CourseDetailData(
      course: const CourseSummary(
        id: 'course-owner-step3',
        slug: 'owner-step3',
        title: 'Owner Step 3',
        description: 'Owner should open course directly',
        createdBy: 'owner-1',
        isFreeIntro: false,
        journeyStep: CourseJourneyStep.step3,
        isPublished: false,
        priceCents: 12900,
      ),
      modules: const [
        CourseModule(
          id: 'module-1',
          courseId: 'course-owner-step3',
          title: 'Modul 1',
          position: 1,
        ),
      ],
      lessonsByModule: const {
        'module-1': [
          LessonSummary(
            id: 'lesson-1',
            title: 'Lektion 1',
            position: 1,
            isIntro: false,
          ),
          LessonSummary(
            id: 'lesson-2',
            title: 'Lektion 2',
            position: 2,
            isIntro: false,
          ),
        ],
      },
      hasAccess: true,
      accessReason: 'teacher',
      isEnrolled: false,
      hasActiveSubscription: false,
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
          authOverride(profile: ownerProfile),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          coursePricingProvider.overrideWith(
            (ref, slug) async =>
                CoursePricing(amountCents: 12900, currency: 'sek'),
          ),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'owner-step3')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Lektion 1'), findsOneWidget);
    expect(find.text('Lektion 2'), findsOneWidget);
    expect(find.text('Starta introduktion'), findsNothing);
    expect(find.textContaining('Köp'), findsNothing);
    expect(find.text('Anmäl'), findsNothing);
  });
}
