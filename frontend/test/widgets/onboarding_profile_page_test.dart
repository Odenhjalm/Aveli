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
import 'package:aveli/data/repositories/profile_repository.dart';
import 'package:aveli/domain/models/entry_state.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/onboarding/onboarding_profile_page.dart';
import 'package:aveli/features/onboarding/welcome_page.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

const _onboardingEntryState = EntryState(
  canEnterApp: false,
  onboardingState: 'incomplete',
  onboardingCompleted: false,
  membershipActive: true,
  needsOnboarding: true,
  needsPayment: false,
  roleV2: 'learner',
  role: 'learner',
  isAdmin: false,
);

Profile _profile({String? displayName, String? bio}) {
  return Profile(
    id: 'user-1',
    email: 'user@example.com',
    createdAt: DateTime.utc(2024, 1, 1),
    updatedAt: DateTime.utc(2024, 1, 1),
    displayName: displayName,
    bio: bio,
  );
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository(this.profile);

  Profile profile;
  int updateCalls = 0;
  String? savedDisplayName;
  String? savedBio;

  @override
  Future<Profile?> getMe() async => profile;

  @override
  Future<Profile> updateMe({String? displayName, String? bio}) async {
    updateCalls += 1;
    savedDisplayName = displayName;
    savedBio = bio;
    profile = profile.copyWith(displayName: displayName, bio: bio);
    return profile;
  }
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this.profileRepository)
    : super(_FakeAuthRepository(), AuthHttpObserver()) {
    state = AuthState(
      profile: profileRepository.profile,
      entryState: _onboardingEntryState,
      hasStoredToken: true,
    );
  }

  final _FakeProfileRepository profileRepository;
  int createProfileCalls = 0;
  int loadSessionCalls = 0;
  int completeWelcomeCalls = 0;
  String? savedDisplayName;
  String? savedBio;
  String? savedReferralCode;

  @override
  Future<void> createProfile({
    required String displayName,
    String? bio,
    String? referralCode,
  }) async {
    createProfileCalls += 1;
    savedDisplayName = displayName;
    savedBio = bio;
    savedReferralCode = referralCode;
    profileRepository.profile = profileRepository.profile.copyWith(
      displayName: displayName,
      bio: bio,
    );
    state = state.copyWith(profile: profileRepository.profile);
  }

  @override
  Future<void> loadSession({bool hydrateProfile = true}) async {
    loadSessionCalls += 1;
    state = state.copyWith(profile: profileRepository.profile);
  }

  @override
  Future<void> completeWelcome() async {
    completeWelcomeCalls += 1;
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<Profile> login({required String email, required String password}) {
    throw UnsupportedError('Not implemented in this test');
  }

  @override
  Future<Profile> register({
    required String email,
    required String password,
  }) {
    throw UnsupportedError('Not implemented in this test');
  }

  @override
  Future<void> sendVerificationEmail(String email) {
    throw UnsupportedError('Not implemented in this test');
  }

  @override
  Future<void> verifyEmail(String token) {
    throw UnsupportedError('Not implemented in this test');
  }

  @override
  Future<void> requestPasswordReset(String email) {
    throw UnsupportedError('Not implemented in this test');
  }

  @override
  Future<void> resetPassword({
    required String newPassword,
    required String token,
  }) {
    throw UnsupportedError('Not implemented in this test');
  }

  @override
  Future<Profile> getCurrentProfile() {
    throw UnsupportedError('Not implemented in this test');
  }

  @override
  Future<Profile> createProfile({
    required String displayName,
    String? bio,
  }) {
    throw UnsupportedError('Not implemented in this test');
  }

  @override
  Future<Profile> completeWelcome() {
    throw UnsupportedError('Not implemented in this test');
  }

  @override
  Future<void> redeemReferral({required String code}) {
    throw UnsupportedError('Not implemented in this test');
  }

  @override
  Future<void> logout() async {}

  @override
  Future<String?> currentToken() async => 'token';
}

GoRouter _router({String? referralCode}) {
  return GoRouter(
    initialLocation: referralCode == null
        ? RoutePath.createProfile
        : '${RoutePath.createProfile}?referral_code=$referralCode',
    routes: [
      GoRoute(
        path: RoutePath.createProfile,
        name: AppRoute.createProfile,
        builder: (context, state) => OnboardingProfilePage(
          referralCode: state.uri.queryParameters['referral_code'],
        ),
      ),
      GoRoute(
        path: RoutePath.welcome,
        name: AppRoute.welcome,
        builder: (context, state) => const Text('welcome-ready'),
      ),
    ],
  );
}

Future<GoRouter> _pumpProfilePage(
  WidgetTester tester,
  _FakeProfileRepository profileRepository,
  _FakeAuthController authController,
  {String? referralCode}
) async {
  final router = _router(referralCode: referralCode);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => authController),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  return router;
}

Future<void> _tapContinue(WidgetTester tester) async {
  final button = find.widgetWithText(
    FilledButton,
    'Fortsätt till välkomststeget',
  );
  tester.widget<FilledButton>(button).onPressed?.call();
}

void main() {
  testWidgets('onboarding profile blocks empty display name', (tester) async {
    final profileRepository = _FakeProfileRepository(_profile());
    final authController = _FakeAuthController(profileRepository);
    final router = await _pumpProfilePage(
      tester,
      profileRepository,
      authController,
    );

    await _tapContinue(tester);
    await tester.pump();

    expect(authController.createProfileCalls, 0);
    expect(authController.loadSessionCalls, 0);
    expect(find.text('Skriv ditt namn för att fortsätta.'), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.createProfile,
    );
  });

  testWidgets('onboarding profile allows empty bio and no profile image', (
    tester,
  ) async {
    final profileRepository = _FakeProfileRepository(_profile());
    final authController = _FakeAuthController(profileRepository);
    final router = await _pumpProfilePage(
      tester,
      profileRepository,
      authController,
    );

    await tester.enterText(find.byType(TextField).first, '  Aveli User  ');
    await _tapContinue(tester);
    await tester.pumpAndSettle();

    expect(authController.createProfileCalls, 1);
    expect(authController.savedDisplayName, 'Aveli User');
    expect(authController.savedBio, '');
    expect(profileRepository.updateCalls, 0);
    expect(authController.loadSessionCalls, 0);
    expect(authController.completeWelcomeCalls, 0);
    expect(router.routeInformationProvider.value.uri.path, RoutePath.welcome);
  });

  testWidgets('onboarding profile redeems referral code after profile save', (
    tester,
  ) async {
    final profileRepository = _FakeProfileRepository(_profile());
    final authController = _FakeAuthController(profileRepository);
    await _pumpProfilePage(
      tester,
      profileRepository,
      authController,
      referralCode: 'REF123',
    );

    expect(
      find.text('Din referenskod kopplas nÃ¤r profilen sparas.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).first, '  Aveli User  ');
    await _tapContinue(tester);
    await tester.pumpAndSettle();

    expect(authController.createProfileCalls, 1);
    expect(authController.savedReferralCode, 'REF123');
    expect(profileRepository.updateCalls, 0);
  });

  testWidgets('welcome step has exact CTA and no profile input fields', (
    tester,
  ) async {
    final profileRepository = _FakeProfileRepository(
      _profile(displayName: 'Aveli User'),
    );
    final authController = _FakeAuthController(profileRepository);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => authController),
          firstFreeIntroCourseProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: WelcomePage()),
      ),
    );
    await tester.pump();

    expect(find.text('Jag förstår hur Aveli fungerar'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Välkommen till Aveli Aveli User'), findsOneWidget);
  });

  testWidgets('welcome completion uses canonical path without profile update', (
    tester,
  ) async {
    final profileRepository = _FakeProfileRepository(
      _profile(displayName: 'Aveli User'),
    );
    final authController = _FakeAuthController(profileRepository);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => authController),
          profileRepositoryProvider.overrideWithValue(profileRepository),
          firstFreeIntroCourseProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: WelcomePage()),
      ),
    );
    await tester.pump();

    final cta = find.widgetWithText(
      GradientButton,
      'Jag förstår hur Aveli fungerar',
    );
    tester.widget<GradientButton>(cta).onPressed?.call();
    await tester.pump();

    expect(authController.completeWelcomeCalls, 1);
    expect(profileRepository.updateCalls, 0);
    expect(find.byType(TextField), findsNothing);
  });
}
