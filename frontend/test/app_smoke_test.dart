import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/core/routing/app_router.dart';
import 'package:aveli/features/landing/presentation/landing_page.dart';
import 'package:aveli/main.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import 'helpers/backend_asset_resolver_stub.dart';

void main() {
  testWidgets('AveliApp shows landing hero', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const LandingPage()),
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
              stripePublishableKey: 'pk_test',
              stripeMerchantDisplayName: 'Aveli',
              subscriptionsEnabled: false,
            ),
          ),
          backendAssetResolverProvider.overrideWith(
            (ref) => TestBackendAssetResolver(),
          ),
          appRouterProvider.overrideWithValue(router),
        ],
        child: const AveliApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Börja idag'), findsOneWidget);
  });
}
