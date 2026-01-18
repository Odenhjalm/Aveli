import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/app_router.dart';
import 'package:aveli/data/models/activity.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/data/models/service.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/presentation/community_page.dart';
import 'package:aveli/features/home/application/home_providers.dart';
import 'package:aveli/features/home/presentation/home_dashboard_page.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/features/payments/data/billing_api.dart';
import 'package:aveli/features/paywall/application/entitlements_notifier.dart';
import 'package:aveli/features/paywall/data/entitlements_api.dart';
import 'package:aveli/features/paywall/domain/entitlements.dart';
import 'package:aveli/main.dart';
import 'test_assets.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(AuthState initialState)
    : super(
        _FakeAuthRepository(
          profile: initialState.profile,
          token: initialState.profile != null || initialState.claims != null
              ? 'token'
              : null,
        ),
        AuthHttpObserver(),
      ) {
    state = initialState;
  }

  @override
  Future<void> loadSession() async {}
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.profile, this.token});

  final Profile? profile;
  final String? token;

  @override
  Future<Profile> login({required String email, required String password}) {
    throw UnsupportedError('Not implemented for tests');
  }

  @override
  Future<Profile> register({
    required String email,
    required String password,
    required String displayName,
  }) {
    throw UnsupportedError('Not implemented for tests');
  }

  @override
  Future<void> requestPasswordReset(String email) {
    throw UnsupportedError('Not implemented for tests');
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String newPassword,
  }) {
    throw UnsupportedError('Not implemented for tests');
  }

  @override
  Future<Profile> getCurrentProfile() async {
    if (profile == null) {
      throw UnsupportedError('No profile available for test');
    }
    return profile!;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<String?> currentToken() async => token;
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
  Future<String> startSubscription({required String plan}) async {
    return '';
  }

  @override
  Future<void> changePlan(String plan) async {}

  @override
  Future<void> cancelSubscription() async {}
}

class _StaticEntitlementsNotifier extends EntitlementsNotifier {
  _StaticEntitlementsNotifier()
    : super(_StubEntitlementsApi(), _StubBillingApi()) {
    state = const EntitlementsState(
      loading: false,
      data: Entitlements(
        membership: MembershipStatus(isActive: true, status: 'active'),
        courses: <String>[],
      ),
    );
  }

  @override
  Future<void> refresh() async {}
}

List<Override> _commonOverrides(AuthState authState) {
  return [
    envInfoProvider.overrideWith((ref) => envInfoOk),
    authControllerProvider.overrideWith(
      (ref) => _FakeAuthController(authState),
    ),
    entitlementsNotifierProvider.overrideWith(
      (ref) => _StaticEntitlementsNotifier(),
    ),
    appConfigProvider.overrideWithValue(
      const AppConfig(
        apiBaseUrl: 'http://localhost',
        stripePublishableKey: 'pk_test',
        stripeMerchantDisplayName: 'Aveli',
        subscriptionsEnabled: false,
      ),
    ),
    homeFeedProvider.overrideWith((ref) => Future.value(const <Activity>[])),
    homeServicesProvider.overrideWith((ref) => Future.value(const <Service>[])),
    landing.popularCoursesProvider.overrideWith(
      (ref) => Future.value(const landing.LandingSectionState(items: [])),
    ),
    communityServicesProvider.overrideWith(
      (ref) => Future.value(const <Service>[]),
    ),
  ];
}

Future<void> _pumpNavigation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  registerTestAssetHandlers();

  testWidgets('Android back pops to previous route instead of exiting', (
    tester,
  ) async {
    final profile = Profile(
      id: 'user-1',
      email: 'user@example.com',
      userRole: UserRole.teacher,
      isAdmin: false,
      createdAt: DateTime.utc(2024, 1, 1),
      updatedAt: DateTime.utc(2024, 1, 1),
      displayName: 'Test User',
    );

    await tester.pumpWidget(
      wrapWithTestAssets(
        ProviderScope(
          overrides: _commonOverrides(AuthState(profile: profile)),
          child: const AveliApp(),
        ),
      ),
    );

    await _pumpNavigation(tester);
    expect(find.byType(HomeDashboardPage), findsOneWidget);

    // Navigate to Community via router (avoids layout-specific buttons).
    final appContext = tester.element(find.byType(MaterialApp));
    final container = ProviderScope.containerOf(appContext);
    final router = container.read(appRouterProvider);
    router.pushNamed(AppRoute.community);
    await _pumpNavigation(tester);
    expect(find.byType(CommunityPage), findsOneWidget);

    // Simulate a back action by popping the current route.
    router.pop();
    await _pumpNavigation(tester);

    expect(find.byType(HomeDashboardPage), findsOneWidget);
    expect(find.byType(CommunityPage), findsNothing);
  });
}
