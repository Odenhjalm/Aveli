import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/models/certificate.dart';
import 'package:aveli/data/models/order.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/presentation/profile_page.dart';
import 'package:aveli/features/courses/application/course_providers.dart'
    as courses;
import 'package:aveli/features/courses/data/courses_repository.dart'
    show CourseSummary;
import 'package:aveli/features/payments/application/payments_providers.dart';
import 'package:aveli/features/payments/presentation/order_history_page.dart';
import 'package:aveli/features/studio/application/studio_providers.dart'
    as studio;
import 'package:aveli/features/studio/application/studio_upload_queue.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/presentation/course_editor_page.dart';
import 'package:aveli/features/studio/presentation/teacher_home_page.dart';
import 'package:aveli/features/teacher/application/bundle_providers.dart';
import 'package:aveli/features/teacher/presentation/course_bundle_page.dart';
import 'package:aveli/shared/widgets/brand_header.dart';
import 'package:aveli/shared/widgets/go_router_back_button.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _FakeAuthController extends AuthController {
  _FakeAuthController() : super(_MockAuthRepository(), AuthHttpObserver()) {
    state = AuthState(
      profile: Profile(
        id: 'user-1',
        email: 'user@example.com',
        userRole: UserRole.user,
        isAdmin: false,
        createdAt: DateTime.utc(2024, 1, 1),
        updatedAt: DateTime.utc(2024, 1, 1),
      ),
    );
  }

  @override
  Future<void> loadSession({bool hydrateProfile = true}) async {}
}

class _MockStudioRepository extends Mock implements StudioRepository {}

class _NoopUploadQueueNotifier extends UploadQueueNotifier {
  _NoopUploadQueueNotifier(super.repo);

  @override
  String enqueueUpload({
    required String courseId,
    required String lessonId,
    required Uint8List data,
    required String filename,
    String? displayName,
    required String contentType,
    required bool isIntro,
  }) {
    return 'noop';
  }

  @override
  void cancelUpload(String id) {}

  @override
  void retryUpload(String id) {}

  @override
  void removeJob(String id) {}
}

Finder _headerBackButton() => find.descendant(
  of: find.byType(BrandHeader).last,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is IconButton &&
        widget.icon is Icon &&
        (widget.icon as Icon).icon == Icons.arrow_back_rounded,
  ),
);

Future<void> _pumpRouter(WidgetTester tester) async {
  // GoRouter updates tend to require an extra pump in widget tests, but we
  // cannot use pumpAndSettle due to loading spinners.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

void main() {
  testWidgets('back navigation is deterministic for profile and purchases', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          name: AppRoute.home,
          builder: (_, _) => const SizedBox(key: ValueKey('home')),
        ),
        GoRoute(
          path: '/profile',
          name: AppRoute.profile,
          builder: (_, _) => const ProfilePage(),
        ),
        GoRoute(
          path: '/orders',
          name: AppRoute.orders,
          builder: (_, _) => const OrderHistoryPage(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _FakeAuthController()),
          myCertificatesProvider.overrideWith((ref) async => <Certificate>[]),
          courses.myCoursesProvider.overrideWith(
            (ref) async => <CourseSummary>[],
          ),
          orderHistoryProvider.overrideWith((ref) async => <Order>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpRouter(tester);

    router.goNamed(AppRoute.profile);
    await _pumpRouter(tester);
    expect(find.byType(GoRouterBackButton), findsNothing);
    await tester.tap(_headerBackButton());
    await _pumpRouter(tester);
    expect(router.routeInformationProvider.value.uri.path, '/home');

    router.goNamed(AppRoute.orders);
    await _pumpRouter(tester);
    expect(find.byType(GoRouterBackButton), findsNothing);
    await tester.tap(_headerBackButton());
    await _pumpRouter(tester);
    expect(router.routeInformationProvider.value.uri.path, '/profile');
  });

  testWidgets('back navigation is deterministic for studio pages', (
    tester,
  ) async {
    final studioRepo = _MockStudioRepository();
    when(() => studioRepo.fetchStatus()).thenAnswer(
      (_) async => const StudioStatus(
        isTeacher: false,
        verifiedCertificates: 0,
        hasApplication: false,
      ),
    );

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          name: AppRoute.home,
          builder: (_, _) => const SizedBox(key: ValueKey('home')),
        ),
        GoRoute(
          path: '/teacher',
          name: AppRoute.teacherHome,
          builder: (_, _) => const TeacherHomeScreen(),
        ),
        GoRoute(
          path: '/teacher/bundles',
          name: AppRoute.teacherBundles,
          builder: (_, _) => const CourseBundlePage(),
        ),
        GoRoute(
          path: '/teacher/editor',
          name: AppRoute.teacherEditor,
          builder: (_, _) => const CourseEditorScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _FakeAuthController()),
          studio.studioRepositoryProvider.overrideWithValue(studioRepo),
          studio.studioUploadQueueProvider.overrideWith(
            (ref) => _NoopUploadQueueNotifier(studioRepo),
          ),
          studio.myCoursesProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[],
          ),
          teacherBundlesProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpRouter(tester);

    router.goNamed(AppRoute.teacherHome);
    await _pumpRouter(tester);
    expect(find.byType(GoRouterBackButton), findsNothing);
    await tester.tap(_headerBackButton());
    await _pumpRouter(tester);
    expect(router.routeInformationProvider.value.uri.path, '/home');

    router.goNamed(AppRoute.teacherBundles);
    await _pumpRouter(tester);
    expect(find.byType(GoRouterBackButton), findsNothing);
    await tester.tap(_headerBackButton());
    await _pumpRouter(tester);
    expect(router.routeInformationProvider.value.uri.path, '/teacher');

    router.goNamed(AppRoute.teacherEditor);
    await _pumpRouter(tester);
    expect(find.byType(GoRouterBackButton), findsNothing);
    await tester.tap(_headerBackButton());
    await _pumpRouter(tester);
    expect(router.routeInformationProvider.value.uri.path, '/teacher');
  });

  testWidgets('brand tap still routes to landing', (tester) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/landing',
          name: AppRoute.landing,
          builder: (_, _) => const SizedBox(key: ValueKey('landing')),
        ),
        GoRoute(
          path: '/home',
          name: AppRoute.home,
          builder: (_, _) => const ProfilePage(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _FakeAuthController()),
          myCertificatesProvider.overrideWith((ref) async => <Certificate>[]),
          courses.myCoursesProvider.overrideWith(
            (ref) async => <CourseSummary>[],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpRouter(tester);

    await tester.tap(find.text('Aveli').last);
    await _pumpRouter(tester);
    expect(router.routeInformationProvider.value.uri.path, '/landing');
  });
}
