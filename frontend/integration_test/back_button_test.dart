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
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/domain/models/entry_state.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/presentation/community_page.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/home/application/home_audio_controller.dart';
import 'package:aveli/features/home/data/home_audio_repository.dart';
import 'package:aveli/features/home/presentation/home_dashboard_page.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/main.dart';
import 'test_assets.dart';

const _testHomeplayerLogo = HomePlayerLogoSet(
  closed: HomePlayerLogoAsset(
    assetKey: 'homeplayer_logo_closed',
    resolvedUrl:
        'https://storage.test/storage/v1/object/public/public-media/home-player/logos/v1/homeplayer_logo_closed.png',
  ),
  open: HomePlayerLogoAsset(
    assetKey: 'homeplayer_logo_open',
    resolvedUrl:
        'https://storage.test/storage/v1/object/public/public-media/home-player/logos/v1/homeplayer_logo_open.png',
  ),
);

class _FakeAuthController extends AuthController {
  _FakeAuthController(AuthState initialState)
    : super(
        _FakeAuthRepository(
          profile: initialState.profile,
          token: initialState.profile != null || initialState.entryState != null
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

class _FakeHomeAudioController extends HomeAudioController {
  @override
  Future<HomeAudioState> build() async => const HomeAudioState(
    items: [],
    homeplayerLogo: _testHomeplayerLogo,
    textBundle: HomePlayerTextBundle(),
  );
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.profile, this.token});

  final Profile? profile;
  final String? token;

  @override
  Future<void> login({required String email, required String password}) {
    throw UnsupportedError('Not implemented for tests');
  }

  @override
  Future<void> register({required String email, required String password}) {
    throw UnsupportedError('Not implemented for tests');
  }

  @override
  Future<void> sendVerificationEmail(String email) {
    throw UnsupportedError('Not implemented for tests');
  }

  @override
  Future<void> verifyEmail(String token) {
    throw UnsupportedError('Not implemented for tests');
  }

  @override
  Future<void> requestPasswordReset(String email) {
    throw UnsupportedError('Not implemented for tests');
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) {
    throw UnsupportedError('Not implemented for tests');
  }

  @override
  Future<Profile> createProfile({required String displayName, String? bio}) {
    throw UnsupportedError('Not implemented for tests');
  }

  @override
  Future<void> redeemReferral({required String code}) {
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
  Future<void> completeWelcome() async {}

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
        subscriptionsEnabled: false,
      ),
    ),
    homeAudioProvider.overrideWith(_FakeHomeAudioController.new),
    coursesProvider.overrideWith((ref) async => const <CourseSummary>[]),
    landing.popularCoursesProvider.overrideWith(
      (ref) async => const landing.LandingSection<CourseSummary>(items: []),
    ),
    notificationsProvider.overrideWith((ref) async => []),
    teacherDirectoryProvider.overrideWith(
      (ref) async => const TeacherDirectoryState(teachers: []),
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
      createdAt: DateTime.utc(2024, 1, 1),
      updatedAt: DateTime.utc(2024, 1, 1),
      displayName: 'Test User',
    );
    const entryState = EntryState(
      canEnterApp: true,
      onboardingState: EntryOnboardingState.completed,
      onboardingCompleted: true,
      membershipActive: true,
      needsOnboarding: false,
      needsPayment: false,
      role: 'teacher',
    );

    await tester.pumpWidget(
      wrapWithTestAssets(
        ProviderScope(
          overrides: _commonOverrides(
            AuthState(
              profile: profile,
              entryState: entryState,
              hasStoredToken: true,
            ),
          ),
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
