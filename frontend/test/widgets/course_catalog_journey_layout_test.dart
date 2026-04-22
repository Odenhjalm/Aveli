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
import 'package:aveli/shared/utils/course_cover_contract.dart';

CourseSummary _course({
  required String id,
  required String slug,
  required String title,
  required int groupPosition,
  String courseGroupId = '',
  int? priceCents,
  String? coverMediaId,
  CourseCoverData? cover,
  bool? enrollable,
  bool? purchasable,
}) {
  final isFreeIntro = groupPosition == 0;
  return CourseSummary(
    id: id,
    slug: slug,
    title: title,
    teacher: const CourseTeacherData(
      userId: 'teacher-1',
      displayName: 'Aveli Teacher',
    ),
    groupPosition: groupPosition,
    courseGroupId: courseGroupId,
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
  );
}

Future<void> _pumpCatalog(
  WidgetTester tester, {
  required List<CourseSummary> courses,
}) async {
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
        coursesProvider.overrideWith((ref) async => courses),
        courseProgressProvider.overrideWith(
          (ref, request) async => const <String, double>{},
        ),
      ],
      child: const MaterialApp(home: CourseCatalogPage()),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void _setLargeSurface(WidgetTester tester) {
  final view = tester.view;
  view.physicalSize = const Size(1800, 2400);
  view.devicePixelRatio = 1.0;
}

void _resetSurface(WidgetTester tester) {
  final view = tester.view;
  view.resetPhysicalSize();
  view.resetDevicePixelRatio();
}

void main() {
  testWidgets('renders a single intro course without fixed progression slots', (
    tester,
  ) async {
    _setLargeSurface(tester);
    addTearDown(() => _resetSurface(tester));

    await _pumpCatalog(
      tester,
      courses: [
        _course(
          id: 'intro-1',
          slug: 'intro-start',
          title: 'Intro Start',
          groupPosition: 0,
          courseGroupId: 'series:solo',
        ),
      ],
    );

    expect(find.text('Intro Start'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('journey-family-row:series:solo')),
      findsNothing,
    );
    expect(find.text('Fler kurser kommer snart.'), findsOneWidget);
    expect(find.text('Steg 1'), findsNothing);
    expect(find.text('Steg 2'), findsNothing);
    expect(find.text('Steg 3'), findsNothing);
  });

  testWidgets(
    'renders multiple progression courses in canonical group_position order',
    (tester) async {
      _setLargeSurface(tester);
      addTearDown(() => _resetSurface(tester));

      await _pumpCatalog(
        tester,
        courses: [
          _course(
            id: 'healing-4',
            slug: 'healing-path-position-4',
            title: 'Healing Path Position 4',
            groupPosition: 4,
            courseGroupId: 'series:healing-path',
            priceCents: 11900,
          ),
          _course(
            id: 'healing-intro',
            slug: 'healing-path-intro',
            title: 'Healing Path Intro',
            groupPosition: 0,
            courseGroupId: 'series:healing-path',
          ),
          _course(
            id: 'healing-2',
            slug: 'healing-path-position-2',
            title: 'Healing Path Position 2',
            groupPosition: 2,
            courseGroupId: 'series:healing-path',
            priceCents: 10900,
          ),
          _course(
            id: 'healing-1',
            slug: 'healing-path-position-1',
            title: 'Healing Path Position 1',
            groupPosition: 1,
            courseGroupId: 'series:healing-path',
            priceCents: 9900,
          ),
          _course(
            id: 'healing-3',
            slug: 'healing-path-position-3',
            title: 'Healing Path Position 3',
            groupPosition: 3,
            courseGroupId: 'series:healing-path',
            priceCents: 11400,
          ),
        ],
      );

      final familyRow = find.byKey(
        const ValueKey('journey-family-row:series:healing-path'),
      );
      final slot1 = find.byKey(
        const ValueKey('journey-course-slot:series:healing-path:position1'),
      );
      final slot2 = find.byKey(
        const ValueKey('journey-course-slot:series:healing-path:position2'),
      );
      final slot3 = find.byKey(
        const ValueKey('journey-course-slot:series:healing-path:position3'),
      );
      final slot4 = find.byKey(
        const ValueKey('journey-course-slot:series:healing-path:position4'),
      );

      expect(familyRow, findsOneWidget);
      expect(slot1, findsOneWidget);
      expect(slot2, findsOneWidget);
      expect(slot3, findsOneWidget);
      expect(slot4, findsOneWidget);
      expect(find.text('Steg 1'), findsNothing);
      expect(find.text('Steg 2'), findsNothing);
      expect(find.text('Steg 3'), findsNothing);
      expect(find.text('Position 4'), findsOneWidget);

      final slot1X = tester.getTopLeft(slot1).dx;
      final slot2X = tester.getTopLeft(slot2).dx;
      final slot3X = tester.getTopLeft(slot3).dx;
      final slot4X = tester.getTopLeft(slot4).dx;
      expect(slot2X, greaterThan(slot1X));
      expect(slot3X, greaterThan(slot2X));
      expect(slot4X, greaterThan(slot3X));
    },
  );

  testWidgets('reordered backend positions win over title or input order', (
    tester,
  ) async {
    _setLargeSurface(tester);
    addTearDown(() => _resetSurface(tester));

    await _pumpCatalog(
      tester,
      courses: [
        _course(
          id: 'reordered-2',
          slug: 'alpha-journey',
          title: 'Alpha Journey',
          groupPosition: 2,
          courseGroupId: 'series:reordered',
          priceCents: 11900,
        ),
        _course(
          id: 'reordered-1',
          slug: 'zen-foundation',
          title: 'Zen Foundation',
          groupPosition: 1,
          courseGroupId: 'series:reordered',
          priceCents: 10900,
        ),
        _course(
          id: 'reordered-intro',
          slug: 'reordered-intro',
          title: 'Reordered Intro',
          groupPosition: 0,
          courseGroupId: 'series:reordered',
        ),
      ],
    );

    final slot1 = find.byKey(
      const ValueKey('journey-course-slot:series:reordered:position1'),
    );
    final slot2 = find.byKey(
      const ValueKey('journey-course-slot:series:reordered:position2'),
    );
    expect(slot1, findsOneWidget);
    expect(slot2, findsOneWidget);

    expect(
      tester.getTopLeft(slot2).dx,
      greaterThan(tester.getTopLeft(slot1).dx),
    );
    expect(
      tester.getTopLeft(find.text('Alpha Journey')).dx,
      greaterThan(tester.getTopLeft(find.text('Zen Foundation')).dx),
    );
  });

  testWidgets('moved courses render under their new family', (tester) async {
    _setLargeSurface(tester);
    addTearDown(() => _resetSurface(tester));

    await _pumpCatalog(
      tester,
      courses: [
        _course(
          id: 'healing-intro',
          slug: 'healing-intro',
          title: 'Healing Intro',
          groupPosition: 0,
          courseGroupId: 'series:healing-path',
        ),
        _course(
          id: 'tarot-intro',
          slug: 'tarot-intro',
          title: 'Tarot Intro',
          groupPosition: 0,
          courseGroupId: 'series:tarot-core',
        ),
        _course(
          id: 'tarot-1',
          slug: 'tarot-position-1',
          title: 'Tarot Position 1',
          groupPosition: 1,
          courseGroupId: 'series:tarot-core',
          priceCents: 10900,
        ),
        _course(
          id: 'moved-course',
          slug: 'moved-course',
          title: 'Moved Course',
          groupPosition: 2,
          courseGroupId: 'series:tarot-core',
          priceCents: 11900,
        ),
      ],
    );

    final tarotRow = find.byKey(
      const ValueKey('journey-family-row:series:tarot-core'),
    );
    expect(tarotRow, findsOneWidget);
    expect(
      find.byKey(const ValueKey('journey-family-row:series:healing-path')),
      findsNothing,
    );
    expect(
      find.descendant(of: tarotRow, matching: find.text('Moved Course')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: tarotRow,
        matching: find.byKey(
          const ValueKey('journey-course-slot:series:tarot-core:position2'),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders premium discovery cover without enrollment state', (
    tester,
  ) async {
    _setLargeSurface(tester);
    addTearDown(() => _resetSurface(tester));

    await _pumpCatalog(
      tester,
      courses: [
        _course(
          id: 'premium-intro',
          slug: 'premium-intro',
          title: 'Premium Intro',
          groupPosition: 0,
          courseGroupId: 'series:premium-course',
        ),
        _course(
          id: 'premium-1',
          slug: 'premium-course',
          title: 'Premium Course',
          groupPosition: 1,
          courseGroupId: 'series:premium-course',
          priceCents: 9900,
          coverMediaId: 'media-1',
          cover: const CourseCoverData(
            mediaId: 'media-1',
            state: 'ready',
            resolvedUrl: 'https://cdn.test/catalog-premium-cover.jpg',
          ),
        ),
      ],
    );

    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url ==
                'https://cdn.test/catalog-premium-cover.jpg',
        description:
            'Image.network(https://cdn.test/catalog-premium-cover.jpg)',
      ),
      findsOneWidget,
    );
    final exception = tester.takeException();
    if (exception != null) {
      expect(exception, isA<NetworkImageLoadException>());
    }
  });

  testWidgets('catalog error state hides raw backend or parser text', (
    tester,
  ) async {
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
          coursesProvider.overrideWith(
            (ref) async =>
                throw StateError('Course not found: backend internal text'),
          ),
        ],
        child: const MaterialApp(home: CourseCatalogPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Kunde inte hämta kurser just nu.'), findsOneWidget);
    expect(find.text('Försök igen om en stund.'), findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.textContaining('Course not found'), findsNothing);
    expect(find.textContaining('backend internal'), findsNothing);
    expect(tester.takeException(), isNull);
  });
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
  Future<Profile> createProfile({required String displayName, String? bio}) =>
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
  Future<Profile> register({required String email, required String password}) =>
      throw UnimplementedError();

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
