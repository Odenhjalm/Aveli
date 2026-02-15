import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/features/paywall/presentation/checkout_return_page.dart';

class _FakeCheckoutApi extends CheckoutApi {
  _FakeCheckoutApi(this._result) : super(baseUrl: 'http://localhost');

  final CheckoutVerificationResult _result;
  String? verifiedSessionId;

  @override
  Future<CheckoutVerificationResult> verifyCheckoutSession({
    required String sessionId,
  }) async {
    verifiedSessionId = sessionId;
    return _result;
  }
}

void main() {
  testWidgets('navigating to /checkout/return verifies session_id', (
    tester,
  ) async {
    final api = _FakeCheckoutApi(
      const CheckoutVerificationResult(
        ok: true,
        sessionId: 'cs_test_123',
        success: false,
        status: 'canceled',
      ),
    );

    final router = GoRouter(
      initialLocation: '${RoutePath.checkoutReturn}?session_id=cs_test_123',
      routes: [
        GoRoute(
          path: RoutePath.checkoutReturn,
          builder: (context, state) => CheckoutReturnPage(
            sessionId: state.uri.queryParameters['session_id'],
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost',
              stripePublishableKey: 'pk_test',
              stripeMerchantDisplayName: 'Aveli',
              subscriptionsEnabled: true,
            ),
          ),
          checkoutApiProvider.overrideWithValue(api),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(api.verifiedSessionId, 'cs_test_123');
    expect(find.text('Checkout uppdaterad'), findsOneWidget);
  });
}
