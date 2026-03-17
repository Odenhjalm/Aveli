import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_router.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/core/routing/route_session.dart';
import 'package:aveli/core/routing/route_extras.dart';
import 'package:aveli/features/onboarding/domain/onboarding_status.dart';

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
        path: RoutePath.resumeOnboarding,
        name: AppRoute.resumeOnboarding,
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
        path: RoutePath.selectIntroCourse,
        name: AppRoute.selectIntroCourse,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.welcome,
        name: AppRoute.welcome,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.checkout,
        name: AppRoute.checkout,
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
    onboarding: null,
  );

  const authedUser = RouteSessionSnapshot(
    isAuthenticated: true,
    isAuthLoading: false,
    hasTentativeSession: false,
    isTeacher: false,
    isAdmin: false,
    onboarding: null,
  );

  const teacher = RouteSessionSnapshot(
    isAuthenticated: true,
    isAuthLoading: false,
    hasTentativeSession: false,
    isTeacher: true,
    isAdmin: false,
    onboarding: null,
  );

  const admin = RouteSessionSnapshot(
    isAuthenticated: true,
    isAuthLoading: false,
    hasTentativeSession: false,
    isTeacher: true,
    isAdmin: true,
    onboarding: null,
  );

  const onboardingProfile = RouteSessionSnapshot(
    isAuthenticated: true,
    isAuthLoading: false,
    hasTentativeSession: false,
    isTeacher: false,
    isAdmin: false,
    onboarding: OnboardingStatus(
      onboardingState: OnboardingStateValue.paidProfileIncomplete,
      nextStep: RoutePath.createProfile,
      emailVerified: true,
      membershipActive: true,
      profileComplete: false,
      introCourseSelected: false,
      onboardingComplete: false,
    ),
  );

  const onboardingSubscribe = RouteSessionSnapshot(
    isAuthenticated: true,
    isAuthLoading: false,
    hasTentativeSession: false,
    isTeacher: false,
    isAdmin: false,
    onboarding: OnboardingStatus(
      onboardingState: OnboardingStateValue.verifiedUnpaid,
      nextStep: RoutePath.subscribe,
      emailVerified: true,
      membershipActive: false,
      profileComplete: false,
      introCourseSelected: false,
      onboardingComplete: false,
    ),
  );

  const onboardingComplete = RouteSessionSnapshot(
    isAuthenticated: true,
    isAuthLoading: false,
    hasTentativeSession: false,
    isTeacher: false,
    isAdmin: false,
    onboarding: OnboardingStatus(
      onboardingState: OnboardingStateValue.onboardingComplete,
      nextStep: RoutePath.home,
      emailVerified: true,
      membershipActive: true,
      profileComplete: true,
      introCourseSelected: true,
      onboardingComplete: true,
    ),
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

  testWidgets(
    'incomplete onboarding redirects authenticated users to next step',
    (tester) async {
      final router = await _pumpHarness(tester, onboardingProfile);

      router.go(RoutePath.home);
      await tester.pump();

      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePath.createProfile,
      );
    },
  );

  testWidgets('subscribe-stage onboarding can stay on checkout success route', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, onboardingSubscribe);

    router.go('${RoutePath.checkoutSuccess}?session_id=cs_test_123');
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.checkoutSuccess,
    );
  });

  testWidgets('completed onboarding redirects managed routes back home', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, onboardingComplete);

    router.go(RoutePath.welcome);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, RoutePath.home);
  });
}
