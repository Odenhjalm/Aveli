import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_router.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/core/routing/route_session.dart';
import 'package:aveli/domain/models/entry_state.dart';

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
        path: RoutePath.landingRoot,
        name: AppRoute.landingRoot,
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
        path: RoutePath.signup,
        name: AppRoute.signup,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.home,
        name: AppRoute.home,
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
        path: RoutePath.checkoutMembership,
        name: AppRoute.checkoutMembership,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.subscribe,
        name: AppRoute.subscribe,
        redirect: (context, state) => RoutePath.checkoutMembership,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.checkoutSuccess,
        name: AppRoute.checkoutSuccess,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.checkoutReturn,
        name: AppRoute.checkoutReturn,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.checkoutHostedCancel,
        name: AppRoute.checkoutHostedCancel,
        builder: (context, _) => const SizedBox.shrink(),
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
    entryState: null,
    isEntryStateLoading: false,
  );

  const completedEntry = RouteSessionSnapshot(
    entryState: EntryState(
      canEnterApp: true,
      onboardingState: EntryOnboardingState.completed,
      onboardingCompleted: true,
      membershipActive: true,
      needsOnboarding: false,
      needsPayment: false,
      roleV2: 'learner',
      role: 'learner',
      isAdmin: false,
    ),
    isEntryStateLoading: false,
  );

  const paymentNeeded = RouteSessionSnapshot(
    entryState: EntryState(
      canEnterApp: false,
      onboardingState: EntryOnboardingState.completed,
      onboardingCompleted: true,
      membershipActive: false,
      needsOnboarding: false,
      needsPayment: true,
      roleV2: 'learner',
      role: 'learner',
      isAdmin: false,
    ),
    isEntryStateLoading: false,
  );

  const ordinaryPaymentAndOnboardingNeeded = RouteSessionSnapshot(
    entryState: EntryState(
      canEnterApp: false,
      onboardingState: EntryOnboardingState.incomplete,
      onboardingCompleted: false,
      membershipActive: false,
      needsOnboarding: true,
      needsPayment: true,
      roleV2: 'learner',
      role: 'learner',
      isAdmin: false,
    ),
    isEntryStateLoading: false,
  );

  const onboardingNeeded = RouteSessionSnapshot(
    entryState: EntryState(
      canEnterApp: false,
      onboardingState: EntryOnboardingState.incomplete,
      onboardingCompleted: false,
      membershipActive: true,
      needsOnboarding: true,
      needsPayment: false,
      roleV2: 'learner',
      role: 'learner',
      isAdmin: false,
    ),
    isEntryStateLoading: false,
  );

  const welcomePending = RouteSessionSnapshot(
    entryState: EntryState(
      canEnterApp: false,
      onboardingState: EntryOnboardingState.welcomePending,
      onboardingCompleted: false,
      membershipActive: true,
      needsOnboarding: true,
      needsPayment: false,
      roleV2: 'learner',
      role: 'learner',
      isAdmin: false,
    ),
    isEntryStateLoading: false,
  );

  const tentativeSession = RouteSessionSnapshot(
    entryState: null,
    isEntryStateLoading: true,
  );

  test('entry state model accepts only canonical onboarding states', () {
    final state = EntryState.fromJson({
      'can_enter_app': false,
      'onboarding_state': EntryOnboardingState.welcomePending,
      'onboarding_completed': false,
      'membership_active': true,
      'needs_onboarding': true,
      'needs_payment': false,
      'role_v2': 'learner',
      'role': 'learner',
      'is_admin': false,
    });

    expect(state.onboardingState, EntryOnboardingState.welcomePending);
    expect(
      () => EntryState.fromJson({
        'can_enter_app': false,
        'onboarding_state': 'profile_created',
        'onboarding_completed': false,
        'membership_active': true,
        'needs_onboarding': true,
        'needs_payment': false,
        'role_v2': 'learner',
        'role': 'learner',
        'is_admin': false,
      }),
      throwsFormatException,
    );
  });

  testWidgets('unauthenticated users redirect private routes to login', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, unauthenticated);

    router.go(RoutePath.home);
    await tester.pump();

    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, RoutePath.login);
    expect(uri.queryParameters['redirect'], RoutePath.home);
  });

  testWidgets('completed backend entry redirects away from login to home', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, completedEntry);

    router.go(RoutePath.login);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, RoutePath.home);
  });

  testWidgets(
    'payment-needed entry state redirects private routes to membership checkout',
    (tester) async {
      final router = await _pumpHarness(tester, paymentNeeded);

      router.go(RoutePath.home);
      await tester.pump();

      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePath.checkoutMembership,
      );
    },
  );

  testWidgets(
    'ordinary both payment and onboarding needed routes to membership checkout',
    (tester) async {
      final router = await _pumpHarness(
        tester,
        ordinaryPaymentAndOnboardingNeeded,
      );

      router.go(RoutePath.home);
      await tester.pump();

      final uri = router.routeInformationProvider.value.uri;
      expect(uri.path, RoutePath.checkoutMembership);
      expect(uri.path, isNot(RoutePath.createProfile));
      expect(uri.queryParameters.containsKey('referral_code'), isFalse);
    },
  );

  testWidgets('/subscribe forwards to membership checkout', (tester) async {
    final router = await _pumpHarness(tester, paymentNeeded);

    router.go(RoutePath.subscribe);
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.checkoutMembership,
    );
  });

  testWidgets(
    'incomplete onboarding redirects private routes to create profile',
    (tester) async {
      final router = await _pumpHarness(tester, onboardingNeeded);

      router.go(RoutePath.home);
      await tester.pump();

      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePath.createProfile,
      );
    },
  );

  testWidgets('onboarding allows create-profile route', (tester) async {
    final router = await _pumpHarness(tester, onboardingNeeded);

    router.go(RoutePath.createProfile);
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.createProfile,
    );
  });

  testWidgets('welcome-pending onboarding allows welcome route', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, welcomePending);

    router.go(RoutePath.welcome);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, RoutePath.welcome);
  });

  testWidgets('welcome-pending onboarding blocks create-profile fallback', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, welcomePending);

    router.go(RoutePath.createProfile);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, RoutePath.welcome);
  });

  testWidgets(
    'welcome-pending onboarding redirects private routes to welcome',
    (tester) async {
      final router = await _pumpHarness(tester, welcomePending);

      router.go(RoutePath.home);
      await tester.pump();

      expect(router.routeInformationProvider.value.uri.path, RoutePath.welcome);
    },
  );

  testWidgets('tentative sessions stabilize on boot while hydrating', (
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

  testWidgets('boot sends unauthenticated private redirects to login', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, unauthenticated);

    router.go(
      '${RoutePath.boot}?redirect=${Uri.encodeComponent(RoutePath.home)}',
    );
    await tester.pump();

    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, RoutePath.login);
    expect(uri.queryParameters['redirect'], RoutePath.home);
  });

  testWidgets('boot sends missing entry state to login with public redirect', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, unauthenticated);

    router.go(
      '${RoutePath.boot}?redirect=${Uri.encodeComponent(RoutePath.checkoutSuccess)}',
    );
    await tester.pump();

    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, RoutePath.login);
    expect(uri.queryParameters['redirect'], RoutePath.checkoutSuccess);
  });

  testWidgets('boot sends completed backend entry to home', (tester) async {
    final router = await _pumpHarness(tester, completedEntry);

    router.go(RoutePath.boot);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, RoutePath.home);
  });

  testWidgets('public checkout success remains accessible while logged out', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, unauthenticated);

    router.go(RoutePath.checkoutSuccess);
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.checkoutSuccess,
    );
  });

  testWidgets(
    'checkout success route does not override backend payment state',
    (tester) async {
      final router = await _pumpHarness(tester, paymentNeeded);

      router.go(RoutePath.checkoutSuccess);
      await tester.pump();

      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePath.checkoutSuccess,
      );

      router.go(RoutePath.home);
      await tester.pump();

      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePath.checkoutMembership,
      );
    },
  );

  testWidgets(
    'checkout return routes to create profile after backend confirms membership',
    (tester) async {
      final router = await _pumpHarness(tester, onboardingNeeded);

      router.go(RoutePath.checkoutReturn);
      await tester.pump();

      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePath.createProfile,
      );
    },
  );
}
