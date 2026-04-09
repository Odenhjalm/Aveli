import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/data/models/profile.dart';
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
      expect(gate.allowed, isTrue);
      verify(() => repo.getCurrentProfile()).called(1);
      verifyNever(() => repo.logout());
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
      when(() => repo.completeWelcome()).thenAnswer((_) async => profile);

      await controller.completeWelcome();

      expect(controller.state.profile, equals(profile));
      expect(controller.state.hasStoredToken, isTrue);
      expect(controller.state.isLoading, isFalse);
      expect(gate.allowed, isTrue);
      verify(() => repo.completeWelcome()).called(1);
    });
  });
}
