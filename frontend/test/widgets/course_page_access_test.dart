import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/features/courses/presentation/course_page.dart';
import 'package:aveli/features/paywall/application/pricing_providers.dart';
import 'package:aveli/features/paywall/data/course_pricing_api.dart';
import 'package:aveli/shared/utils/course_cover_contract.dart';
import 'package:aveli/shared/utils/course_journey_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _FakeTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> updateAccessToken(String accessToken) async {}
}

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
  const resolvedContractUiEnabled = bool.fromEnvironment(
    'COURSE_COVER_RESOLVED_UI_ENABLED',
    defaultValue: false,
  );
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

  MediaRepository buildMediaRepository(String apiBaseUrl) {
    final client = ApiClient(
      baseUrl: apiBaseUrl,
      tokenStorage: _FakeTokenStorage(),
    );
    return MediaRepository(
      client: client,
      config: AppConfig(
        apiBaseUrl: apiBaseUrl,
        stripePublishableKey: 'pk_test',
        stripeMerchantDisplayName: 'Aveli Test',
        subscriptionsEnabled: true,
      ),
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

  testWidgets(
    'renders flat lessons with synthetic module and no module title requirement',
    (tester) async {
      final detail = CourseDetailData(
        course: const CourseSummary(
          id: 'course-flat',
          slug: 'flat-lessons-course',
          title: 'Flat Lessons',
          description: 'Course with flat lesson payload',
          isFreeIntro: false,
          isPublished: true,
          priceCents: 0,
        ),
        modules: const [
          CourseModule(
            id: flatLessonsModuleId,
            courseId: 'course-flat',
            title: '',
            position: 0,
          ),
        ],
        lessonsByModule: const {
          flatLessonsModuleId: [
            LessonSummary(
              id: 'lesson-1',
              title: 'L1',
              position: 1,
              isIntro: true,
            ),
            LessonSummary(
              id: 'lesson-2',
              title: 'L2',
              position: 2,
              isIntro: false,
            ),
          ],
        },
        hasAccess: true,
        accessReason: 'enrolled',
        isEnrolled: true,
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
                  CoursePricing(amountCents: 0, currency: 'sek'),
            ),
          ],
          child: const MaterialApp(
            home: CoursePage(slug: 'flat-lessons-course'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('L1'), findsOneWidget);
      expect(find.text('L2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'prefers backend resolved cover over legacy cover url when the frontend flag is enabled',
    (tester) async {
      final detail = CourseDetailData(
        course: const CourseSummary(
          id: 'course-cover-contract',
          slug: 'course-cover-contract',
          title: 'Cover Contract',
          description: 'Resolved cover should win when enabled',
          coverUrl: '/api/files/public-media/legacy-cover.png',
          cover: CourseCoverData(
            mediaId: 'cover-1',
            state: 'ready',
            resolvedUrl: '/api/files/public-media/resolved-cover.png',
            source: 'control_plane',
          ),
          isFreeIntro: true,
          isPublished: true,
          priceCents: 0,
        ),
        modules: const [
          CourseModule(
            id: flatLessonsModuleId,
            courseId: 'course-cover-contract',
            title: '',
            position: 0,
          ),
        ],
        lessonsByModule: const {
          flatLessonsModuleId: [
            LessonSummary(
              id: 'lesson-1',
              title: 'Intro',
              position: 1,
              isIntro: true,
            ),
          ],
        },
        hasAccess: false,
        accessReason: '',
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
            mediaRepositoryProvider.overrideWithValue(
              buildMediaRepository('http://localhost:8080'),
            ),
            authOverride(),
            courseDetailProvider.overrideWith((ref, slug) async => detail),
            coursePricingProvider.overrideWith(
              (ref, slug) async =>
                  CoursePricing(amountCents: 0, currency: 'sek'),
            ),
          ],
          child: const MaterialApp(
            home: CoursePage(slug: 'course-cover-contract'),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final imageException = tester.takeException();
      expect(imageException, anyOf(isNull, isA<NetworkImageLoadException>()));

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is NetworkImage &&
              (widget.image as NetworkImage).url ==
                  'http://localhost:8080/api/files/public-media/resolved-cover.png',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is NetworkImage &&
              (widget.image as NetworkImage).url ==
                  'http://localhost:8080/api/files/public-media/legacy-cover.png',
        ),
        findsNothing,
      );
    },
    skip: !resolvedContractUiEnabled,
  );
}
