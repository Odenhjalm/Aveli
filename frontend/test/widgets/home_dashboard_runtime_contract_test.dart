import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/models/certificate.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/data/models/service.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/home/application/home_providers.dart';
import 'package:aveli/features/home/presentation/home_dashboard_page.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/features/seminars/application/seminar_providers.dart';
import 'package:aveli/shared/utils/backend_assets.dart';

import '../helpers/backend_asset_resolver_stub.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(AuthState initial)
    : super(_StubAuthRepository(), AuthHttpObserver()) {
    state = initial;
  }

  @override
  Future<void> loadSession({bool hydrateProfile = true}) async {}
}

class _StubAuthRepository implements AuthRepository {
  @override
  Future<Profile> login({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<Profile> register({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> sendVerificationEmail(String email) async {}

  @override
  Future<void> verifyEmail(String token) async {}

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> resetPassword({
    required String newPassword,
    required String token,
  }) async {}

  @override
  Future<Profile> getCurrentProfile() => throw UnimplementedError();

  @override
  Future<Profile> createProfile({
    required String displayName,
    String? bio,
  }) =>
      throw UnimplementedError();

  @override
  Future<Profile> completeWelcome() => throw UnimplementedError();

  @override
  Future<void> redeemReferral({required String code}) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<String?> currentToken() async => null;
}

final _testProfile = Profile(
  id: 'user-1',
  email: 'user@test.local',
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 1),
);

Future<void> _pumpDashboard(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: AppRoute.home,
        builder: (context, state) => const HomeDashboardPage(),
      ),
      GoRoute(
        path: '/login',
        name: AppRoute.login,
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: '/services/:id',
        name: AppRoute.serviceDetail,
        builder: (context, state) => const SizedBox.shrink(),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(AuthState(profile: _testProfile)),
        ),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'https://api.test',
            subscriptionsEnabled: false,
          ),
        ),
        backendAssetResolverProvider.overrideWith(
          (ref) => TestBackendAssetResolver(),
        ),
        homeFeedProvider.overrideWith((ref) async => const []),
        homeServicesProvider.overrideWith((ref) async => const <Service>[]),
        coursesProvider.overrideWith((ref) async => const []),
        landing.popularCoursesProvider.overrideWith(
          (ref) async =>
              const landing.LandingSection<landing.LandingCourseCard>(
                items: [],
              ),
        ),
        publicSeminarsProvider.overrideWith((ref) async => const []),
        myCertificatesProvider.overrideWith(
          (ref) async => const <Certificate>[],
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  for (var i = 0; i < 5; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets(
    'home dashboard renders current runtime sections without audio provider',
    (tester) async {
      await _pumpDashboard(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Utforska kurser'), findsOneWidget);
      expect(find.text('Gemensam vägg'), findsOneWidget);
      expect(find.text('Tjänster'), findsOneWidget);
    },
  );
}
