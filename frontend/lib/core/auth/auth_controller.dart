import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_claims.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/gate.dart';

@immutable
class AuthState {
  const AuthState({
    this.profile,
    this.claims,
    this.isLoading = false,
    this.error,
  });

  final Profile? profile;
  final AuthClaims? claims;
  final bool isLoading;
  final String? error;

  AuthState copyWith({
    Profile? profile,
    AuthClaims? claims,
    bool? isLoading,
    String? error,
    bool clearClaims = false,
  }) => AuthState(
    profile: profile ?? this.profile,
    claims: clearClaims ? null : (claims ?? this.claims),
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );

  /// Verified auth: JWT claims alone are *not* sufficient.
  bool get isAuthenticated => profile != null;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repo, this._authObserver) : super(const AuthState()) {
    _authSub = _authObserver.events.listen(_handleAuthEvent);
  }

  final AuthRepository _repo;
  final AuthHttpObserver _authObserver;
  late final StreamSubscription<AuthHttpEvent> _authSub;

  Future<void> loadSession({bool hydrateProfile = true}) async {
    // Mark bootstrap as loading immediately (before any async awaits) so routing
    // can gate private routes behind verified auth without rendering jitter.
    state = state.copyWith(isLoading: true, error: null);
    final token = await _repo.currentToken();
    if (token == null || token.isEmpty) {
      gate.reset();
      state = const AuthState();
      return;
    }

    final claims = AuthClaims.fromToken(token);
    state = state.copyWith(
      isLoading: hydrateProfile,
      error: null,
      claims: claims,
    );

    if (!hydrateProfile) {
      state = state.copyWith(isLoading: false);
      return;
    }

    await _hydrateProfile();
  }

  Future<void> hydrateProfile() async {
    if (state.profile != null || state.isLoading) return;
    await _hydrateProfile();
  }

  Future<void> _hydrateProfile() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final profile = await _repo.getCurrentProfile();
      state = state.copyWith(profile: profile, isLoading: false);
      gate.allow();
    } catch (err, stackTrace) {
      await _repo.logout();
      gate.reset();
      final failure = AppFailure.from(err, stackTrace);
      state = AuthState(
        profile: null,
        claims: null,
        isLoading: false,
        error: failure.message,
      );
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null, clearClaims: true);
    try {
      final profile = await _repo.login(email: email, password: password);
      final token = await _repo.currentToken();
      final claims = token != null ? AuthClaims.fromToken(token) : null;
      state = AuthState(profile: profile, claims: claims, isLoading: false);
      gate.allow();
    } catch (err, stackTrace) {
      final failure = AppFailure.from(err, stackTrace);
      state = AuthState(
        profile: null,
        claims: null,
        isLoading: false,
        error: failure.message,
      );
      gate.reset();
      throw failure;
    }
  }

  Future<void> register(
    String email,
    String password, {
    String? displayName,
    String? referralCode,
    String? inviteToken,
  }) async {
    state = state.copyWith(isLoading: true, error: null, clearClaims: true);
    try {
      final profile = await _repo.register(
        email: email,
        password: password,
        displayName: displayName?.trim().isNotEmpty == true
            ? displayName!.trim()
            : email.split('@').first,
        referralCode: referralCode,
        inviteToken: inviteToken,
      );
      final token = await _repo.currentToken();
      final claims = token != null ? AuthClaims.fromToken(token) : null;
      state = AuthState(profile: profile, claims: claims, isLoading: false);
      gate.allow();
    } catch (err, stackTrace) {
      final failure = AppFailure.from(err, stackTrace);
      state = AuthState(
        profile: null,
        claims: null,
        isLoading: false,
        error: failure.message,
      );
      gate.reset();
      throw failure;
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    gate.reset();
    state = const AuthState();
  }

  Future<void> completeWelcome() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repo.completeWelcome();
      await loadSession();
    } catch (err, stackTrace) {
      final failure = AppFailure.from(err, stackTrace);
      state = state.copyWith(isLoading: false, error: failure.message);
      throw failure;
    }
  }

  void _handleAuthEvent(AuthHttpEvent event) {
    switch (event) {
      case AuthHttpEvent.sessionExpired:
        unawaited(_handleSessionExpired());
      case AuthHttpEvent.forbidden:
        break;
    }
  }

  Future<void> _handleSessionExpired() async {
    await _repo.logout();
    gate.reset();
    state = const AuthState();
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    final repo = ref.watch(authRepositoryProvider);
    final observer = ref.watch(authHttpObserverProvider);
    final controller = AuthController(repo, observer);
    controller.loadSession();
    return controller;
  },
);
