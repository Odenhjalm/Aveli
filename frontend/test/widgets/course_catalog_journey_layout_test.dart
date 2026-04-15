import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_catalog_page.dart';
import 'package:aveli/shared/utils/course_journey_step.dart';

CourseSummary _course({
  required String id,
  required String slug,
  required String title,
  required CourseJourneyStep step,
  String courseGroupId = '',
  int? priceCents,
}) {
  return CourseSummary(
    id: id,
    slug: slug,
    title: title,
    step: step,
    courseGroupId: courseGroupId,
    coverMediaId: null,
    cover: null,
    priceCents: priceCents,
    dripEnabled: false,
    dripIntervalDays: null,
  );
}

void main() {
  testWidgets(
    'renders each journey progression as its own fixed three-slot band',
    (tester) async {
      final view = tester.view;
      view.physicalSize = const Size(1600, 2400);
      view.devicePixelRatio = 1.0;
      addTearDown(() {
        view.resetPhysicalSize();
        view.resetDevicePixelRatio();
      });

      final previewCourses = <CourseSummary>[
        _course(
          id: 'intro-1',
          slug: 'intro-start',
          title: 'Intro',
          step: CourseJourneyStep.intro,
        ),
        _course(
          id: 'healing-1',
          slug: 'healing-path-step-1',
          title: 'Healing Path Steg 1',
          step: CourseJourneyStep.step1,
          courseGroupId: 'series:healing-path',
          priceCents: 9900,
        ),
        _course(
          id: 'healing-2',
          slug: 'healing-path-step-2',
          title: 'Healing Path Steg 2',
          step: CourseJourneyStep.step2,
          courseGroupId: 'series:healing-path',
          priceCents: 10900,
        ),
        _course(
          id: 'tarot-1',
          slug: 'tarot-core-step-1',
          title: 'Tarot Core Steg 1',
          step: CourseJourneyStep.step1,
          courseGroupId: 'series:tarot-core',
          priceCents: 12900,
        ),
        _course(
          id: 'tarot-2',
          slug: 'tarot-core-step-2',
          title: 'Tarot Core Steg 2',
          step: CourseJourneyStep.step2,
          courseGroupId: 'series:tarot-core',
          priceCents: 13900,
        ),
        _course(
          id: 'tarot-3',
          slug: 'tarot-core-step-3',
          title: 'Tarot Core Steg 3',
          step: CourseJourneyStep.step3,
          courseGroupId: 'series:tarot-core',
          priceCents: 14900,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(
                apiBaseUrl: 'https://api.test',
                subscriptionsEnabled: false,
              ),
            ),
            authControllerProvider.overrideWith(
              (ref) => _FakeAuthController(const AuthState()),
            ),
            coursesProvider.overrideWith((ref) async => previewCourses),
            courseProgressProvider.overrideWith(
              (ref, request) async => const <String, double>{},
            ),
          ],
          child: const MaterialApp(home: CourseCatalogPage()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final healingRow = find.byKey(
        const ValueKey('journey-series-row:series:healing-path'),
      );
      final tarotRow = find.byKey(
        const ValueKey('journey-series-row:series:tarot-core'),
      );
      final healingEmptyStep3 = find.byKey(
        const ValueKey('journey-empty-slot:series:healing-path:step3'),
      );
      final healingStep1Slot = find.byKey(
        const ValueKey('journey-slot:series:healing-path:step1'),
      );
      final healingStep3Slot = find.byKey(
        const ValueKey('journey-slot:series:healing-path:step3'),
      );

      expect(healingRow, findsOneWidget);
      expect(tarotRow, findsOneWidget);
      expect(healingEmptyStep3, findsOneWidget);
      expect(
        find.descendant(of: tarotRow, matching: find.text('Tarot Core Steg 3')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: healingRow,
          matching: find.text('Tarot Core Steg 3'),
        ),
        findsNothing,
      );

      final healingRowTop = tester.getTopLeft(healingRow).dy;
      final tarotRowTop = tester.getTopLeft(tarotRow).dy;
      expect(tarotRowTop, greaterThan(healingRowTop + 40));

      final healingStep1Size = tester.getSize(healingStep1Slot);
      final healingStep3Size = tester.getSize(healingStep3Slot);
      expect(healingStep3Size.width, closeTo(healingStep1Size.width, 0.1));
      expect(healingStep3Size.height, closeTo(healingStep1Size.height, 0.1));
    },
  );

  testWidgets(
    'keeps live del-based journey courses in one band when titles and slugs are inconsistent',
    (tester) async {
      final view = tester.view;
      view.physicalSize = const Size(1600, 2400);
      view.devicePixelRatio = 1.0;
      addTearDown(() {
        view.resetPhysicalSize();
        view.resetDevicePixelRatio();
      });

      final previewCourses = <CourseSummary>[
        _course(
          id: 'intro-1',
          slug: 'intro-start',
          title: 'Intro',
          step: CourseJourneyStep.intro,
        ),
        _course(
          id: 'herbs-1',
          slug: 'utbildning-sjalvlakande-orter-och-nutrition-ax8b-hfrn5g87js',
          title: 'Utbildning Självläkande örter & nutrition del 1',
          step: CourseJourneyStep.step1,
          courseGroupId: 'series:utbildning-självläkande-örter-nutrition',
          priceCents: 85000,
        ),
        _course(
          id: 'herbs-2',
          slug:
              'utbildning-sjalvlakande-orter-och-nutrition-del-2-1v3d-hfrncjb1c8',
          title: 'Utbildning Självläkande örter & nutrition del 2',
          step: CourseJourneyStep.step2,
          courseGroupId: 'series:utbildning-självläkande-örter-nutrition',
          priceCents: 65000,
        ),
        _course(
          id: 'meditation-3',
          slug: 'utbildning-spirituell-meditation-del-3-l460-hfrms0fis0',
          title: 'Utbildning Spirituell meditation del 3 Meditationscoach',
          step: CourseJourneyStep.step3,
          courseGroupId: 'series:utbildning-spirituell-meditation',
          priceCents: 198000,
        ),
        _course(
          id: 'meditation-2',
          slug: 'utbildning-spirituell-meditation-del-2-1274-hfrmnf8wug',
          title: 'Utbildning Spirituell meditation del 2',
          step: CourseJourneyStep.step2,
          courseGroupId: 'series:utbildning-spirituell-meditation',
          priceCents: 155000,
        ),
        _course(
          id: 'meditation-1',
          slug: 'utbildning-spirituell-meditation-del-1-8m5g-hfrmdjn6yo',
          title: 'Utbildning Spirituell Meditation del 1',
          step: CourseJourneyStep.step1,
          courseGroupId: 'series:utbildning-spirituell-meditation',
          priceCents: 65000,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(
                apiBaseUrl: 'https://api.test',
                subscriptionsEnabled: false,
              ),
            ),
            authControllerProvider.overrideWith(
              (ref) => _FakeAuthController(const AuthState()),
            ),
            coursesProvider.overrideWith((ref) async => previewCourses),
            courseProgressProvider.overrideWith(
              (ref, request) async => const <String, double>{},
            ),
          ],
          child: const MaterialApp(home: CourseCatalogPage()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final herbsRow = find.byKey(
        const ValueKey(
          'journey-series-row:series:utbildning-självläkande-örter-nutrition',
        ),
      );
      final meditationRow = find.byKey(
        const ValueKey(
          'journey-series-row:series:utbildning-spirituell-meditation',
        ),
      );

      expect(herbsRow, findsOneWidget);
      expect(meditationRow, findsOneWidget);
      expect(
        find.byKey(
          const ValueKey(
            'journey-empty-slot:series:utbildning-spirituell-meditation:step1',
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey(
            'journey-empty-slot:series:utbildning-spirituell-meditation:step2',
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: meditationRow,
          matching: find.text(
            'Utbildning Spirituell meditation del 3 Meditationscoach',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: meditationRow,
          matching: find.text('Utbildning Spirituell Meditation del 1'),
        ),
        findsOneWidget,
      );
    },
  );
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(AuthState initial)
    : super(_StubAuthRepository(), AuthHttpObserver()) {
    state = initial;
  }

  @override
  Future<void> loadSession({bool hydrateProfile = true}) async {}
}

class _StubAuthRepository implements AuthRepository {
  @override
  Future<Profile> completeWelcome() => throw UnimplementedError();

  @override
  Future<Profile> createProfile({
    required String displayName,
    String? bio,
  }) =>
      throw UnimplementedError();

  @override
  Future<Profile> getCurrentProfile() => throw UnimplementedError();

  @override
  Future<void> redeemReferral({required String code}) async {}

  @override
  Future<Profile> login({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<String?> currentToken() async => null;

  @override
  Future<Profile> register({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {}

  @override
  Future<void> sendVerificationEmail(String email) async {}

  @override
  Future<void> verifyEmail(String token) async {}
}
