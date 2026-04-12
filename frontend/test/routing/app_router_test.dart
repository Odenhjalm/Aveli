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
        path: RoutePath.subscribe,
        name: AppRoute.subscribe,
        builder: (context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RoutePath.checkoutSuccess,
        name: AppRoute.checkoutSuccess,
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
      onboardingCompleted: true,
      membershipActive: true,
      needsOnboarding: false,
      needsPayment: false,
      isInvite: false,
    ),
    isEntryStateLoading: false,
  );

  const paymentNeeded = RouteSessionSnapshot(
    entryState: EntryState(
      canEnterApp: false,
      onboardingCompleted: true,
      membershipActive: false,
      needsOnboarding: false,
      needsPayment: true,
      isInvite: false,
    ),
    isEntryStateLoading: false,
  );

  const onboardingNeeded = RouteSessionSnapshot(
    entryState: EntryState(
      canEnterApp: false,
      onboardingCompleted: false,
      membershipActive: true,
      needsOnboarding: true,
      needsPayment: false,
      isInvite: true,
    ),
    isEntryStateLoading: false,
  );

  const onboardingNeededWithName = RouteSessionSnapshot(
    entryState: EntryState(
      canEnterApp: false,
      onboardingCompleted: false,
      membershipActive: true,
      needsOnboarding: true,
      needsPayment: false,
      isInvite: true,
    ),
    isEntryStateLoading: false,
    profileDisplayName: 'Aveli User',
  );

  const onboardingNeededNonInvite = RouteSessionSnapshot(
    entryState: EntryState(
      canEnterApp: false,
      onboardingCompleted: false,
      membershipActive: true,
      needsOnboarding: true,
      needsPayment: false,
      isInvite: false,
    ),
    isEntryStateLoading: false,
  );

  const onboardingNeededNonInviteWithName = RouteSessionSnapshot(
    entryState: EntryState(
      canEnterApp: false,
      onboardingCompleted: false,
      membershipActive: true,
      needsOnboarding: true,
      needsPayment: false,
      isInvite: false,
    ),
    isEntryStateLoading: false,
    profileDisplayName: 'Aveli User',
  );

  const onboardingNeededWithBlankName = RouteSessionSnapshot(
    entryState: EntryState(
      canEnterApp: false,
      onboardingCompleted: false,
      membershipActive: true,
      needsOnboarding: true,
      needsPayment: false,
      isInvite: true,
    ),
    isEntryStateLoading: false,
    profileDisplayName: '   ',
  );

  const tentativeSession = RouteSessionSnapshot(
    entryState: null,
    isEntryStateLoading: true,
  );

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
    'payment-needed entry state redirects private routes to subscribe',
    (tester) async {
      final router = await _pumpHarness(tester, paymentNeeded);

      router.go(RoutePath.home);
      await tester.pump();

      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePath.subscribe,
      );
    },
  );

  testWidgets('onboarding without profile name redirects to create profile', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, onboardingNeeded);

    router.go(RoutePath.home);
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.createProfile,
    );
  });

  testWidgets('non-invite onboarding without profile name creates profile', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, onboardingNeededNonInvite);

    router.go(RoutePath.home);
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.createProfile,
    );
  });

  testWidgets(
    'onboarding with blank profile name redirects to create profile',
    (tester) async {
      final router = await _pumpHarness(tester, onboardingNeededWithBlankName);

      router.go(RoutePath.home);
      await tester.pump();

      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePath.createProfile,
      );
    },
  );

  testWidgets(
    'onboarding with profile name redirects private routes to welcome',
    (tester) async {
      final router = await _pumpHarness(tester, onboardingNeededWithName);

      router.go(RoutePath.home);
      await tester.pump();

      expect(router.routeInformationProvider.value.uri.path, RoutePath.welcome);
    },
  );

  testWidgets('non-invite onboarding with profile name redirects to welcome', (
    tester,
  ) async {
    final router = await _pumpHarness(
      tester,
      onboardingNeededNonInviteWithName,
    );

    router.go(RoutePath.home);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, RoutePath.welcome);
  });

  testWidgets(
    'onboarding with profile name redirects profile step to welcome',
    (tester) async {
      final router = await _pumpHarness(tester, onboardingNeededWithName);

      router.go(RoutePath.createProfile);
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
}
