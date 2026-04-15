import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/domain/models/entry_state.dart';
import 'package:aveli/gate.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  group('AuthController', () {
    late _MockAuthRepository repo;
    late AuthController controller;
    late AuthHttpObserver observer;

    final profile = Profile(
      id: 'user-1',
      email: 'user@example.com',
      createdAt: DateTime.utc(2024, 1, 1),
      updatedAt: DateTime.utc(2024, 1, 1),
      displayName: 'Test User',
    );
    const entryState = EntryState(
      canEnterApp: true,
      onboardingState: 'completed',
      onboardingCompleted: true,
      membershipActive: true,
      needsOnboarding: false,
      needsPayment: false,
      roleV2: 'learner',
      role: 'learner',
      isAdmin: false,
    );

    setUp(() {
      repo = _MockAuthRepository();
      observer = AuthHttpObserver();
      controller = AuthController(repo, observer);
      gate.reset();
    });

    tearDown(() {
      observer.dispose();
    });

    test('loadSession hydrates profile when a token exists', () async {
      when(() => repo.currentToken()).thenAnswer((_) async => 'token');
      when(() => repo.getCurrentProfile()).thenAnswer((_) async => profile);

      await controller.loadSession();

      expect(controller.state.profile, equals(profile));
      expect(controller.state.hasStoredToken, isTrue);
      expect(controller.state.isLoading, isFalse);
      expect(gate.allowed, isFalse);
      verify(() => repo.getCurrentProfile()).called(1);
      verifyNever(() => repo.logout());
    });

    test('loadSession stores backend-owned entry state', () async {
      var entryStateLoads = 0;
      controller.dispose();
      controller = AuthController(
        repo,
        observer,
        loadEntryState: () async {
          entryStateLoads += 1;
          return entryState;
        },
      );
      when(() => repo.currentToken()).thenAnswer((_) async => 'token');
      when(() => repo.getCurrentProfile()).thenAnswer((_) async => profile);

      await controller.loadSession();

      expect(controller.state.profile, equals(profile));
      expect(controller.state.entryState, equals(entryState));
      expect(controller.state.isAuthenticated, isTrue);
      expect(entryStateLoads, 1);
    });

    test('profile without backend entry state is not app-entry', () {
      final state = AuthState(profile: profile, hasStoredToken: true);

      expect(state.isAuthenticated, isFalse);
    });

    test('loadSession clears auth state when no token exists', () async {
      when(() => repo.currentToken()).thenAnswer((_) async => null);

      await controller.loadSession();

      expect(controller.state, const AuthState());
      expect(gate.allowed, isFalse);
      verifyNever(() => repo.getCurrentProfile());
      verifyNever(() => repo.logout());
    });

    test('sessionExpired logs out and clears state', () async {
      when(() => repo.logout()).thenAnswer((_) async {});
      controller.state = AuthState(
        profile: profile,
        hasStoredToken: true,
        isLoading: false,
      );
      gate.allow();

      observer.emit(AuthHttpEvent.sessionExpired);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, const AuthState());
      expect(gate.allowed, isFalse);
      verify(() => repo.logout()).called(1);
    });

    test('completeWelcome replaces state with the refreshed profile', () async {
      controller.dispose();
      controller = AuthController(
        repo,
        observer,
        loadEntryState: () async => entryState,
      );
      when(() => repo.completeWelcome()).thenAnswer((_) async => profile);

      await controller.completeWelcome();

      expect(controller.state.profile, equals(profile));
      expect(controller.state.entryState, equals(entryState));
      expect(controller.state.hasStoredToken, isTrue);
      expect(controller.state.isLoading, isFalse);
      expect(gate.allowed, isFalse);
      verify(() => repo.completeWelcome()).called(1);
    });

    test('createProfile stores onboarding-created profile and entry state', () async {
      final createdProfile = profile.copyWith(
        displayName: 'Aveli User',
        bio: 'Kort bio',
      );
      controller.dispose();
      controller = AuthController(
        repo,
        observer,
        loadEntryState: () async => entryState,
      );
      when(
        () => repo.createProfile(
          displayName: 'Aveli User',
          bio: 'Kort bio',
        ),
      ).thenAnswer((_) async => createdProfile);

      await controller.createProfile(
        displayName: 'Aveli User',
        bio: 'Kort bio',
      );

      expect(controller.state.profile, equals(createdProfile));
      expect(controller.state.entryState, equals(entryState));
      expect(controller.state.hasStoredToken, isTrue);
      expect(controller.state.isLoading, isFalse);
      expect(gate.allowed, isFalse);
      verify(
        () => repo.createProfile(
          displayName: 'Aveli User',
          bio: 'Kort bio',
        ),
      ).called(1);
      verifyNever(() => repo.getCurrentProfile());
    });

    test('createProfile redeems referral code before loading entry state', () async {
      final createdProfile = profile.copyWith(displayName: 'Aveli User');
      var entryStateLoads = 0;
      controller.dispose();
      controller = AuthController(
        repo,
        observer,
        loadEntryState: () async {
          entryStateLoads += 1;
          return entryState;
        },
      );
      when(
        () => repo.createProfile(displayName: 'Aveli User', bio: null),
      ).thenAnswer((_) async => createdProfile);
      when(
        () => repo.redeemReferral(code: 'REF123'),
      ).thenAnswer((_) async {});

      await controller.createProfile(
        displayName: 'Aveli User',
        referralCode: ' REF123 ',
      );

      expect(controller.state.profile, equals(createdProfile));
      expect(controller.state.entryState, equals(entryState));
      expect(entryStateLoads, 1);
      verify(
        () => repo.createProfile(displayName: 'Aveli User', bio: null),
      ).called(1);
      verify(() => repo.redeemReferral(code: 'REF123')).called(1);
    });

    test(
      'completeWelcome does not grant entry without active membership',
      () async {
        const paymentNeededEntryState = EntryState(
          canEnterApp: false,
          onboardingState: 'completed',
          onboardingCompleted: true,
          membershipActive: false,
          needsOnboarding: false,
          needsPayment: true,
          roleV2: 'learner',
          role: 'learner',
          isAdmin: false,
        );
        controller.dispose();
        controller = AuthController(
          repo,
          observer,
          loadEntryState: () async => paymentNeededEntryState,
        );
        when(() => repo.completeWelcome()).thenAnswer((_) async => profile);

        await controller.completeWelcome();

        expect(controller.state.profile, equals(profile));
        expect(controller.state.entryState, equals(paymentNeededEntryState));
        expect(controller.state.canEnterApp, isFalse);
        expect(controller.state.isAuthenticated, isFalse);
        expect(gate.allowed, isFalse);
        verify(() => repo.completeWelcome()).called(1);
      },
    );
  });
}
