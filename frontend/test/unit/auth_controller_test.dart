import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/auth/auth_claims.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/gate.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

String _tokenForClaims(Map<String, Object?> claims) {
  final header = base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}'));
  final payload = base64Url.encode(utf8.encode(jsonEncode(claims)));
  return '$header.$payload.signature';
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('AuthController.loadSession', () {
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

    setUp(() {
      repo = _MockAuthRepository();
      observer = AuthHttpObserver();
      controller = AuthController(repo, observer);
      gate.reset();
    });

    tearDown(() {
      observer.dispose();
    });

    test('hydrates profile when token exists', () async {
      when(() => repo.currentToken()).thenAnswer((_) async => 'token');
      when(() => repo.getCurrentProfile()).thenAnswer((_) async => profile);

      await controller.loadSession();

      expect(controller.state.profile, equals(profile));
      expect(controller.state.isLoading, isFalse);
      expect(gate.allowed, isTrue);
      verify(() => repo.getCurrentProfile()).called(1);
      verifyNever(() => repo.logout());
    });

    test('skips profile fetch when hydrateProfile is false', () async {
      when(() => repo.currentToken()).thenAnswer((_) async => 'token');

      await controller.loadSession(hydrateProfile: false);

      expect(controller.state.profile, isNull);
      expect(controller.state.isLoading, isFalse);
      expect(gate.allowed, isFalse);
      verifyNever(() => repo.getCurrentProfile());
      verifyNever(() => repo.logout());
    });

    test('clears state when no token stored', () async {
      when(() => repo.currentToken()).thenAnswer((_) async => null);

      await controller.loadSession();

      expect(controller.state.profile, isNull);
      expect(controller.state.claims, isNull);
      expect(gate.allowed, isFalse);
      verifyNever(() => repo.getCurrentProfile());
    });

    test('logout and reset when profile fetch fails', () async {
      when(() => repo.currentToken()).thenAnswer((_) async => 'token');
      when(() => repo.getCurrentProfile()).thenThrow(Exception('oops'));
      when(() => repo.logout()).thenAnswer((_) async {});

      await controller.loadSession();

      expect(controller.state.profile, isNull);
      expect(controller.state.error, isNotEmpty);
      expect(gate.allowed, isFalse);
      verify(() => repo.logout()).called(1);
    });

    test('sessionExpired event clears state and logs out', () async {
      when(() => repo.logout()).thenAnswer((_) async {});

      controller.state = AuthState(
        profile: profile,
        claims: const AuthClaims(role: 'teacher', isAdmin: false),
      );
      gate.allow();

      observer.emit(AuthHttpEvent.sessionExpired);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.profile, isNull);
      expect(controller.state.claims, isNull);
      expect(gate.allowed, isFalse);
      verify(() => repo.logout()).called(1);
    });

    test('completeWelcome refreshes the hydrated profile', () async {
      final refreshedToken = _tokenForClaims({
        'role': 'teacher',
        'is_admin': false,
        'onboarding_state': OnboardingStateValue.completed,
      });
      when(() => repo.completeWelcome()).thenAnswer((_) async {});
      when(() => repo.currentToken()).thenAnswer((_) async => refreshedToken);
      when(() => repo.getCurrentProfile()).thenAnswer((_) async => profile);

      await controller.completeWelcome();

      expect(
        controller.state.claims?.onboardingState,
        OnboardingStateValue.completed,
      );
      verify(() => repo.completeWelcome()).called(1);
      verify(() => repo.getCurrentProfile()).called(1);
    });
  });
}
