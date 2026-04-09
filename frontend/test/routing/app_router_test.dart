import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_router.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/core/routing/route_session.dart';

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
    isAuthenticated: false,
    isAuthLoading: false,
    hasTentativeSession: false,
  );

  const authenticated = RouteSessionSnapshot(
    isAuthenticated: true,
    isAuthLoading: false,
    hasTentativeSession: false,
  );

  const tentativeSession = RouteSessionSnapshot(
    isAuthenticated: false,
    isAuthLoading: false,
    hasTentativeSession: true,
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

  testWidgets('authenticated users are redirected away from login', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, authenticated);

    router.go(RoutePath.login);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, RoutePath.home);
  });

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

  testWidgets('boot sends unauthenticated public redirects to landing', (
    tester,
  ) async {
    final router = await _pumpHarness(tester, unauthenticated);

    router.go(
      '${RoutePath.boot}?redirect=${Uri.encodeComponent(RoutePath.checkoutSuccess)}',
    );
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.landingRoot,
    );
  });

  testWidgets('boot sends authenticated users to home', (tester) async {
    final router = await _pumpHarness(tester, authenticated);

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
