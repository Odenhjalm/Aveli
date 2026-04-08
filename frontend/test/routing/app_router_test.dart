import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_router.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_extras.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/core/routing/route_session.dart';
import 'package:aveli/data/models/profile.dart';

class _RouterHarness extends ConsumerWidget {
  const _RouterHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(routerConfig: router);
  }
}

final _testAppRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(appRouterNotifierProvider);
  return GoRouter(
    initialLocation: RoutePath.landing,
    refreshListenable: notifier,
    redirect: (context, state) => notifier.handleRedirect(state),
    routes: [
      GoRoute(
        path: RoutePath.boot,
        name: AppRoute.boot,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.landing,
        name: AppRoute.landing,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.login,
        name: AppRoute.login,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.home,
        name: AppRoute.home,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.verifyEmail,
        name: AppRoute.verifyEmail,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.subscribe,
        name: AppRoute.subscribe,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.createProfile,
        name: AppRoute.createProfile,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.welcome,
        name: AppRoute.welcome,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.checkoutSuccess,
        name: AppRoute.checkoutSuccess,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.checkoutCancel,
        name: AppRoute.checkoutCancel,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.adminMedia,
        name: AppRoute.adminMedia,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.teacherHome,
        name: AppRoute.teacherHome,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.teacherEditor,
        name: AppRoute.teacherEditor,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.courseQuiz,
        name: AppRoute.courseQuiz,
        builder: (_, state) {
          final extra = state.extra;
          final quizId = extra is QuizRouteArgs
              ? extra.quizId
              : state.uri.queryParameters['quizId'] ?? 'none';
          return Text('quiz:$quizId');
        },
      ),
      GoRoute(
        path: RoutePath.community,
        name: AppRoute.community,
        builder: (_, state) {
          final extra = state.extra;
          final tab = extra is CommunityRouteArgs
              ? extra.initialTab ?? 'teachers'
              : state.uri.queryParameters['tab'] ?? 'teachers';
          return Text('community:$tab');
        },
      ),
    ],
  );
});

Future<GoRouter> _pumpHarness(
  WidgetTester tester,
  RouteSessionSnapshot session,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        routeSessionSnapshotProvider.overrideWithValue(session),
        appRouterProvider.overrideWith(
          (ref) => ref.watch(_testAppRouterProvider),
        ),
      ],
      child: const _RouterHarness(),
    ),
  );

  final container = ProviderScope.containerOf(
    tester.element(find.byType(_RouterHarness)),
  );
  return container.read(appRouterProvider);
}

void main() {
  const unauthenticated = RouteSessionSnapshot(
    isAuthenticated: false,
    isAuthLoading: false,
    hasTentativeSession: false,
    isTeacher: false,
    isAdmin: false,
  );

  const authedUser = RouteSessionSnapshot(
    isAuthenticated: true,
    isAuthLoading: false,
    hasTentativeSession: false,
    isTeacher: false,
    isAdmin: false,
    onboardingState: OnboardingStateValue.completed,
  );

  const teacher = RouteSessionSnapshot(
    isAuthenticated: true,
    isAuthLoading: false,
    hasTentativeSession: false,
    isTeacher: true,
    isAdmin: false,
    onboardingState: OnboardingStateValue.completed,
  );

  const incompleteProfile = RouteSessionSnapshot(
    isAuthenticated: true,
    isAuthLoading: false,
    hasTentativeSession: false,
    isTeacher: false,
    isAdmin: false,
    onboardingState: OnboardingStateValue.incomplete,
  );

  const admin = RouteSessionSnapshot(
    isAuthenticated: true,
    isAuthLoading: false,
    hasTentativeSession: false,
    isTeacher: false,
    isAdmin: true,
    onboardingState: OnboardingStateValue.completed,
  );

  const tentativeSession = RouteSessionSnapshot(
    isAuthenticated: false,
    isAuthLoading: false,
    hasTentativeSession: true,
    isTeacher: false,
    isAdmin: false,
  );

  testWidgets('unauthenticated users redirect to login with redirect query', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, unauthenticated);

    router.go(RoutePath.home);
    await tester.pump();

    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, RoutePath.login);
    expect(uri.queryParameters['redirect'], RoutePath.home);
  });

  testWidgets('authenticated users hitting /login are sent to /home', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, authedUser);

    router.go(RoutePath.login);
    await tester.pump();

    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, RoutePath.home);
  });

  testWidgets('teachers are sent to teacher home after auth redirects', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, teacher);

    router.go(RoutePath.login);
    await tester.pump();

    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, RoutePath.teacherHome);
  });

  testWidgets('admins bypass onboarding redirects and land on home', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, admin);

    router.go(RoutePath.login);
    await tester.pump();

    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, RoutePath.home);
  });

  testWidgets('tentative sessions stabilize on /boot during hydration', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, tentativeSession);

    router.go(RoutePath.home);
    await tester.pump();

    final firstUri = router.routeInformationProvider.value.uri;
    expect(firstUri.path, RoutePath.boot);
    expect(firstUri.queryParameters['redirect'], RoutePath.home);

    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, RoutePath.boot);
  });

  testWidgets(
    'users with incomplete profile are routed to /create-profile',
    (tester) async {
      final router = await _pumpHarness(tester, incompleteProfile);

      router.go(RoutePath.home);
      await tester.pump();

      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePath.createProfile,
      );
    },
  );

  testWidgets('completed users stay on /home', (tester) async {
    final router = await _pumpHarness(tester, authedUser);

    router.go(RoutePath.home);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, RoutePath.home);
  });

  testWidgets(
    'completed users are redirected away from /create-profile',
    (tester) async {
      final router = await _pumpHarness(tester, authedUser);

      router.go(RoutePath.createProfile);
      await tester.pump();

      expect(router.routeInformationProvider.value.uri.path, RoutePath.home);
    },
  );

  testWidgets('checkout success page is allowed during incomplete onboarding', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, incompleteProfile);

    router.go(RoutePath.checkoutSuccess);
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.checkoutSuccess,
    );
  });

  testWidgets('non-teachers cannot access teacher dashboard routes', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, authedUser);

    router.go(RoutePath.teacherHome);
    await tester.pump();

    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, RoutePath.home);
  });

  testWidgets('non-admins cannot access media control routes', (tester) async {
    final router = await _pumpHarness(tester, authedUser);

    router.go(RoutePath.adminMedia);
    await tester.pump();

    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, RoutePath.home);
  });

  testWidgets('teachers can stay on teacher routes', (tester) async {
    final router = await _pumpHarness(tester, teacher);

    router.go(RoutePath.teacherHome);
    await tester.pump();
    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.teacherHome,
    );

    router.go(RoutePath.teacherEditor);
    await tester.pump();
    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.teacherEditor,
    );
  });

  testWidgets('admins can stay on media control routes', (tester) async {
    final router = await _pumpHarness(tester, admin);

    router.go(RoutePath.adminMedia);
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.adminMedia,
    );
  });

  testWidgets('course quiz route reads extras for quiz id', (tester) async {
    final router = await _pumpHarness(tester, authedUser);

    router.goNamed(
      AppRoute.courseQuiz,
      extra: const QuizRouteArgs(quizId: 'quiz-42'),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('quiz:quiz-42'), findsOneWidget);
  });

  testWidgets('community route honours extras for tab selection', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, authedUser);

    router.goNamed(
      AppRoute.community,
      extra: const CommunityRouteArgs(initialTab: 'services'),
      queryParameters: const {'tab': 'services'},
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('community:services'), findsOneWidget);
  });
}
