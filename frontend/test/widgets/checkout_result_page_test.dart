import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/payments/data/billing_api.dart';
import 'package:aveli/features/paywall/application/entitlements_notifier.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/features/paywall/data/entitlements_api.dart';
import 'package:aveli/features/paywall/domain/entitlements.dart';
import 'package:aveli/features/paywall/presentation/checkout_result_page.dart';

import '../helpers/test_assets.dart';

class _StubAuthRepository implements AuthRepository {
  @override
  Future<Profile> login({required String email, required String password}) {
    throw UnsupportedError('Not implemented in tests');
  }

  @override
  Future<AuthRegisterResult> register({
    required String email,
    required String password,
    required String displayName,
    String? inviteToken,
    String? referralCode,
  }) {
    throw UnsupportedError('Not implemented in tests');
  }

  @override
  Future<void> sendVerificationEmail(String email) async {}

  @override
  Future<String> validateInvite(String token) {
    throw UnsupportedError('Not implemented in tests');
  }

  @override
  Future<VerifyEmailResult> verifyEmail(String token) {
    throw UnsupportedError('Not implemented in tests');
  }

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> resetPassword({
    required String newPassword,
    required String token,
  }) async {}

  @override
  Future<Profile> getCurrentProfile() {
    throw UnsupportedError('Not implemented in tests');
  }

  @override
  Future<void> logout() async {}

  @override
  Future<String?> currentToken() async => null;
}

class _TrackingAuthController extends AuthController {
  _TrackingAuthController() : super(_StubAuthRepository(), AuthHttpObserver());

  int refreshOnboardingCalls = 0;

  @override
  Future<void> loadSession({bool hydrateProfile = true}) async {}

  @override
  Future<void> refreshOnboarding() async {
    refreshOnboardingCalls += 1;
  }
}

class _TrackingCheckoutApi extends CheckoutApi {
  _TrackingCheckoutApi(this._responses) : super(baseUrl: 'https://api.test');

  final Queue<Map<String, dynamic>> _responses;
  int fetchSessionStatusCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchSessionStatus(String sessionId) async {
    fetchSessionStatusCalls += 1;
    return _responses.isEmpty
        ? <String, dynamic>{'membership_status': 'active'}
        : _responses.removeFirst();
  }
}

class _StubEntitlementsApi implements EntitlementsApi {
  @override
  Future<Entitlements> fetchEntitlements() async {
    return const Entitlements(
      membership: MembershipStatus(isActive: true, status: 'active'),
      courses: <String>[],
    );
  }
}

class _StubBillingApi implements BillingApi {
  @override
  Future<String> startSubscription({required String plan}) async => '';

  @override
  Future<void> changePlan(String plan) async {}

  @override
  Future<void> cancelSubscription() async {}
}

class _TrackingEntitlementsNotifier extends EntitlementsNotifier {
  _TrackingEntitlementsNotifier()
    : super(_StubEntitlementsApi(), _StubBillingApi());

  int refreshCalls = 0;

  @override
  Future<void> refresh() async {
    refreshCalls += 1;
  }
}

Future<void> _pumpCheckoutResultPage(
  WidgetTester tester, {
  required String initialLocation,
  required _TrackingCheckoutApi checkoutApi,
  required _TrackingEntitlementsNotifier entitlementsNotifier,
  required _TrackingAuthController authController,
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: RoutePath.checkoutSuccess,
        builder: (context, state) => CheckoutResultPage(
          success: true,
          sessionId: state.uri.queryParameters['session_id'],
          errored: state.uri.queryParameters['errored'] == '1',
        ),
      ),
      GoRoute(
        path: RoutePath.checkoutCancel,
        builder: (context, state) => CheckoutResultPage(
          success: false,
          sessionId: state.uri.queryParameters['session_id'],
        ),
      ),
      GoRoute(
        path: RoutePath.resumeOnboarding,
        builder: (context, state) => const Text('resume-onboarding'),
      ),
    ],
  );

  await tester.pumpWidget(
    wrapWithTestAssets(
      ProviderScope(
        overrides: [
          checkoutApiProvider.overrideWithValue(checkoutApi),
          entitlementsNotifierProvider.overrideWith(
            (ref) => entitlementsNotifier,
          ),
          authControllerProvider.overrideWith((ref) => authController),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerTestAssetHandlers();
  });

  testWidgets(
    'checkout success polls by session query and resumes onboarding',
    (tester) async {
      final checkoutApi = _TrackingCheckoutApi(
        Queue<Map<String, dynamic>>.of([
          <String, dynamic>{'membership_status': 'pending', 'poll_after_ms': 0},
          <String, dynamic>{'membership_status': 'active'},
        ]),
      );
      final entitlementsNotifier = _TrackingEntitlementsNotifier();
      final authController = _TrackingAuthController();

      await _pumpCheckoutResultPage(
        tester,
        initialLocation: '${RoutePath.checkoutSuccess}?session_id=cs_test_123',
        checkoutApi: checkoutApi,
        entitlementsNotifier: entitlementsNotifier,
        authController: authController,
      );

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(checkoutApi.fetchSessionStatusCalls, 2);
      expect(entitlementsNotifier.refreshCalls, 1);
      expect(authController.refreshOnboardingCalls, 1);
      expect(find.text('resume-onboarding'), findsOneWidget);
    },
  );

  testWidgets('checkout cancel skips polling and resumes onboarding', (
    tester,
  ) async {
    final checkoutApi = _TrackingCheckoutApi(Queue<Map<String, dynamic>>());
    final entitlementsNotifier = _TrackingEntitlementsNotifier();
    final authController = _TrackingAuthController();

    await _pumpCheckoutResultPage(
      tester,
      initialLocation: RoutePath.checkoutCancel,
      checkoutApi: checkoutApi,
      entitlementsNotifier: entitlementsNotifier,
      authController: authController,
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(checkoutApi.fetchSessionStatusCalls, 0);
    expect(entitlementsNotifier.refreshCalls, 0);
    expect(authController.refreshOnboardingCalls, 1);
    expect(find.text('resume-onboarding'), findsOneWidget);
  });
}
