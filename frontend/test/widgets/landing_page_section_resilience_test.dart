import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/features/landing/presentation/landing_page.dart';
import 'package:aveli/shared/utils/backend_assets.dart';

import '../helpers/backend_asset_resolver_stub.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<void> login({required String email, required String password}) async {}

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> sendVerificationEmail(String email) async {}

  @override
  Future<void> verifyEmail(String token) async {}

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {}

  @override
  Future<Profile> getCurrentProfile() {
    throw UnsupportedError('No profile available for landing page test');
  }

  @override
  Future<Profile> createProfile({required String displayName, String? bio}) {
    throw UnsupportedError('Not used in landing page test');
  }

  @override
  Future<void> redeemReferral({required String code}) async {}

  @override
  Future<void> completeWelcome() async {}

  @override
  Future<void> logout() async {}

  @override
  Future<String?> currentToken() async => null;
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(AuthState initialState)
    : super(_FakeAuthRepository(), AuthHttpObserver()) {
    state = initialState;
  }

  @override
  Future<void> loadSession({bool hydrateProfile = true}) async {}
}

void main() {
  testWidgets(
    'teachers render when services fails on the public landing page',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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
            authControllerProvider.overrideWith(
              (ref) => _FakeAuthController(const AuthState()),
            ),
            landing.popularCoursesProvider.overrideWith(
              (ref) async =>
                  const landing.LandingSection<CourseSummary>(items: []),
            ),
            landing.introCoursesProvider.overrideWith(
              (ref) async =>
                  const landing.LandingSection<CourseSummary>(items: []),
            ),
            landing.recentServicesProvider.overrideWith((ref) async {
              throw StateError('services failed');
            }),
            landing.teachersProvider.overrideWith(
              (ref) async =>
                  const landing.LandingSection<landing.LandingTeacher>(
                    items: [
                      landing.LandingTeacher(
                        id: 'a101fb71-7cee-4c28-b429-7534d787abeb',
                        displayName: 'Lise-Lotte',
                        avatarUrl: null,
                        bio: 'Teacher bio',
                      ),
                    ],
                  ),
            ),
          ],
          child: const MaterialApp(home: LandingPage()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.scrollUntilVisible(
        find.text('Lise-Lotte'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(find.text('Lise-Lotte'), findsOneWidget);
      expect(find.text('Logga in'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
