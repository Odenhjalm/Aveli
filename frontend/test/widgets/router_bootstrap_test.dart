import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/data/models/activity.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/data/models/service.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/home/application/home_providers.dart';
import 'package:aveli/features/home/presentation/home_dashboard_page.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/features/landing/presentation/landing_page.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/main.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import '../helpers/backend_asset_resolver_stub.dart';
import '../helpers/test_assets.dart';

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
  Future<void> loadSession({bool hydrateProfile = true}) async {}
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.profile, this.token});

  final Profile? profile;
  final String? token;

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
  Future<void> sendVerificationEmail(String email) {
    throw UnsupportedError('Not implemented in tests');
  }

  @override
  Future<String> validateInvite(String token) {
    throw UnsupportedError('Not implemented in tests');
  }

  @override
  Future<VerifyEmailResult> verifyEmail(String token) {
    throw UnsupportedError('Not implemented in tests');
  }

  @override
  Future<void> requestPasswordReset(String email) {
    throw UnsupportedError('Not implemented in tests');
  }

  @override
  Future<void> resetPassword({
    required String newPassword,
    required String token,
  }) {
    throw UnsupportedError('Not implemented in tests');
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

List<Override> _commonOverrides(AuthState authState) {
  return [
    envInfoProvider.overrideWith((ref) => envInfoOk),
    authControllerProvider.overrideWith(
      (ref) => _FakeAuthController(authState),
    ),
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
    homeFeedProvider.overrideWith((ref) => Future.value(const <Activity>[])),
    homeServicesProvider.overrideWith((ref) => Future.value(const <Service>[])),
    landing.introCoursesProvider.overrideWith(
      (ref) => Future.value(const landing.LandingSectionState(items: [])),
    ),
    landing.popularCoursesProvider.overrideWith(
      (ref) => Future.value(const landing.LandingSectionState(items: [])),
    ),
    landing.teachersProvider.overrideWith(
      (ref) => Future.value(const landing.LandingSectionState(items: [])),
    ),
    landing.recentServicesProvider.overrideWith(
      (ref) => Future.value(const landing.LandingSectionState(items: [])),
    ),
    communityServicesProvider.overrideWith(
      (ref) => Future.value(const <Service>[]),
    ),
  ];
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerTestAssetHandlers();
  });

  testWidgets('unauthenticated users land on the landing page first', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithTestAssets(
        ProviderScope(
          overrides: _commonOverrides(const AuthState()),
          child: const AveliApp(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(LandingPage), findsOneWidget);
    expect(find.byType(HomeDashboardPage), findsNothing);
  });

  testWidgets('authenticated users start on home without landing flash', (
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

    final authedState = AuthState(profile: profile, isLoading: false);

    await tester.pumpWidget(
      wrapWithTestAssets(
        ProviderScope(
          overrides: _commonOverrides(authedState),
          child: const AveliApp(),
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(LandingPage), findsNothing);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(HomeDashboardPage), findsOneWidget);
    expect(find.byType(LandingPage), findsNothing);
  });

  testWidgets('AppScaffold shows a home action by default', (tester) async {
    final view = tester.view;
    view.physicalSize = const Size(1200, 800);
    view.devicePixelRatio = 1.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
        ],
        child: const MaterialApp(
          home: AppScaffold(
            title: 'Test',
            body: SizedBox.shrink(),
            neutralBackground: true,
            logoSize: 48,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
  });
}
