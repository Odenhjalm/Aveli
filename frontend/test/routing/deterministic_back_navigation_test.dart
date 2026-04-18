import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/brand_header.dart';
import 'package:aveli/shared/widgets/go_router_back_button.dart';

Finder _headerBackButton() => find.descendant(
  of: find.byType(BrandHeader).last,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is IconButton &&
        widget.icon is Icon &&
        (widget.icon as Icon).icon == Icons.arrow_back_rounded,
  ),
);

AppScaffold _page({
  required String title,
  required Widget body,
  required VoidCallback onBack,
}) {
  return AppScaffold(title: title, onBack: onBack, body: body);
}

Future<void> _pumpRouter(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

void main() {
  testWidgets('back navigation is deterministic for profile and subscription', (
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
          builder: (context, _) => _page(
            title: 'Profil',
            onBack: () => context.goNamed(AppRoute.home),
            body: const SizedBox(key: ValueKey('profile')),
          ),
        ),
        GoRoute(
          path: '/profile/subscription',
          name: AppRoute.profileSubscription,
          builder: (context, _) => _page(
            title: 'Prenumeration',
            onBack: () => context.goNamed(AppRoute.profile),
            body: const SizedBox(key: ValueKey('subscription')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _pumpRouter(tester);

    router.goNamed(AppRoute.profile);
    await _pumpRouter(tester);
    expect(find.byType(GoRouterBackButton), findsNothing);
    await tester.tap(_headerBackButton());
    await _pumpRouter(tester);
    expect(router.routeInformationProvider.value.uri.path, '/home');

    router.pushNamed(AppRoute.profileSubscription);
    await _pumpRouter(tester);
    expect(find.byType(GoRouterBackButton), findsNothing);
    await tester.tap(_headerBackButton());
    await _pumpRouter(tester);
    expect(router.routeInformationProvider.value.uri.path, '/profile');
  });

  testWidgets('back navigation is deterministic for studio pages', (
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
          path: '/teacher',
          name: AppRoute.teacherHome,
          builder: (context, _) => _page(
            title: 'Lararvy',
            onBack: () => context.goNamed(AppRoute.home),
            body: const SizedBox(key: ValueKey('teacher')),
          ),
        ),
        GoRoute(
          path: '/teacher/bundles',
          name: AppRoute.teacherBundles,
          builder: (context, _) => _page(
            title: 'Paket',
            onBack: () => context.goNamed(AppRoute.teacherHome),
            body: const SizedBox(key: ValueKey('bundles')),
          ),
        ),
        GoRoute(
          path: '/teacher/editor',
          name: AppRoute.teacherEditor,
          builder: (context, _) => _page(
            title: 'Editor',
            onBack: () => context.goNamed(AppRoute.teacherHome),
            body: const SizedBox(key: ValueKey('editor')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
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
          builder: (context, _) => _page(
            title: 'Hem',
            onBack: () {},
            body: const SizedBox(key: ValueKey('home')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _pumpRouter(tester);

    await tester.tap(find.text('Aveli').last);
    await _pumpRouter(tester);
    expect(router.routeInformationProvider.value.uri.path, '/landing');
  });
}
