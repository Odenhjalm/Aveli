import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/core/routing/app_router.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/main.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import '../helpers/backend_asset_resolver_stub.dart';
import '../helpers/test_asset_bundle.dart';

void main() {
  setUpAll(installTestAssetBundle);

  testWidgets('forbidden admin users access redirects back home', (
    tester,
  ) async {
    final observer = AuthHttpObserver();
    final router = await _pumpAppAtPath(
      tester,
      RoutePath.adminUsers,
      observer: observer,
    );

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.adminUsers,
    );

    observer.emit(AuthHttpEvent.forbidden);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(router.routeInformationProvider.value.uri.path, RoutePath.home);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('forbidden admin settings access redirects back home', (
    tester,
  ) async {
    final observer = AuthHttpObserver();
    final router = await _pumpAppAtPath(
      tester,
      RoutePath.adminSettings,
      observer: observer,
    );

    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.adminSettings,
    );

    observer.emit(AuthHttpEvent.forbidden);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(router.routeInformationProvider.value.uri.path, RoutePath.home);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}

Future<GoRouter> _pumpAppAtPath(
  WidgetTester tester,
  String initialPath, {
  required AuthHttpObserver observer,
}) async {
  final router = GoRouter(
    initialLocation: initialPath,
    routes: [
      GoRoute(
        path: RoutePath.home,
        name: AppRoute.home,
        builder: (context, state) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: RoutePath.adminUsers,
        name: AppRoute.adminUsers,
        builder: (context, state) => const Scaffold(body: Text('admin-users')),
      ),
      GoRoute(
        path: RoutePath.adminSettings,
        name: AppRoute.adminSettings,
        builder: (context, state) =>
            const Scaffold(body: Text('admin-settings')),
      ),
      GoRoute(
        path: RoutePath.admin,
        name: AppRoute.admin,
        builder: (context, state) => const Scaffold(body: Text('admin')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        envInfoProvider.overrideWith((ref) => envInfoOk),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://localhost',
            subscriptionsEnabled: false,
          ),
        ),
        backendAssetResolverProvider.overrideWith(
          (ref) => TestBackendAssetResolver(),
        ),
        authHttpObserverProvider.overrideWithValue(observer),
        appRouterProvider.overrideWithValue(router),
      ],
      child: const AveliApp(),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return router;
}
