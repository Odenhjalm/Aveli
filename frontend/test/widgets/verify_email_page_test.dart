import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/auth/presentation/verify_email_page.dart';
import 'package:aveli/features/onboarding/domain/onboarding_status.dart';

import '../helpers/test_assets.dart';

class _FakeVerifyAuthRepository implements AuthRepository {
  _FakeVerifyAuthRepository(this.result);

  final VerifyEmailResult result;
  int verifyCalls = 0;

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
  Future<VerifyEmailResult> verifyEmail(String token) async {
    verifyCalls += 1;
    return result;
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
  _TrackingAuthController(AuthRepository repo)
    : super(repo, AuthHttpObserver());

  int loadSessionCalls = 0;

  @override
  Future<void> loadSession({bool hydrateProfile = true}) async {
    loadSessionCalls += 1;
  }
}

Future<GoRouter> _pumpVerifyPage(
  WidgetTester tester, {
  required _FakeVerifyAuthRepository repo,
  required _TrackingAuthController controller,
}) async {
  final router = GoRouter(
    initialLocation: '${RoutePath.verifyEmail}?token=test-token',
    routes: [
      GoRoute(
        path: RoutePath.verifyEmail,
        name: AppRoute.verifyEmail,
        builder: (context, state) =>
            VerifyEmailPage(token: state.uri.queryParameters['token']),
      ),
      GoRoute(
        path: RoutePath.createProfile,
        name: AppRoute.createProfile,
        builder: (context, state) => const Text('create-profile'),
      ),
      GoRoute(
        path: RoutePath.login,
        name: AppRoute.login,
        builder: (context, state) =>
            Text('login:${state.uri.queryParameters['redirect'] ?? ''}'),
      ),
    ],
  );

  await tester.pumpWidget(
    wrapWithTestAssets(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          authControllerProvider.overrideWith((ref) => controller),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    ),
  );
  return router;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerTestAssetHandlers();
  });

  testWidgets('verify page follows onboarding next_step', (tester) async {
    const onboarding = OnboardingStatus(
      onboardingState: OnboardingStateValue.paidProfileIncomplete,
      nextStep: RoutePath.createProfile,
      emailVerified: true,
      membershipActive: true,
      profileComplete: false,
      introCourseSelected: false,
      onboardingComplete: false,
    );
    final repo = _FakeVerifyAuthRepository(
      VerifyEmailResult(status: 'verified', onboarding: onboarding),
    );
    final controller = _TrackingAuthController(repo);

    final router = await _pumpVerifyPage(
      tester,
      repo: repo,
      controller: controller,
    );
    await tester.pumpAndSettle();

    expect(repo.verifyCalls, 1);
    expect(controller.loadSessionCalls, 1);
    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.createProfile,
    );
    expect(find.text('create-profile'), findsOneWidget);
  });

  testWidgets('verify page preserves login continuation without session', (
    tester,
  ) async {
    final repo = _FakeVerifyAuthRepository(
      VerifyEmailResult(
        status: 'verified',
        redirectAfterLogin: RoutePath.resumeOnboarding,
      ),
    );
    final controller = _TrackingAuthController(repo);

    final router = await _pumpVerifyPage(
      tester,
      repo: repo,
      controller: controller,
    );
    await tester.pumpAndSettle();

    expect(repo.verifyCalls, 1);
    expect(controller.loadSessionCalls, 1);
    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, RoutePath.login);
    expect(uri.queryParameters['redirect'], RoutePath.resumeOnboarding);
  });
}
