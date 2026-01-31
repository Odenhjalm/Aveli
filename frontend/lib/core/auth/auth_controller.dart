import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_claims.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/route_access.dart';
import 'package:aveli/core/routing/route_access_resolver.dart';
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
  }) async {
    state = state.copyWith(isLoading: true, error: null, clearClaims: true);
    try {
      final profile = await _repo.register(
        email: email,
        password: password,
        displayName: displayName?.trim().isNotEmpty == true
            ? displayName!.trim()
            : email.split('@').first,
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
    final shouldHydrateProfile = !kIsWeb
        ? true
        : resolveRouteAccessLevel(_initialBootstrapPath()) !=
              RouteAccessLevel.public;
    controller.loadSession(hydrateProfile: shouldHydrateProfile);
    return controller;
  },
);

String _initialBootstrapPath() {
  if (!kIsWeb) return Uri.base.path;
  final uri = Uri.base;
  final fragment = uri.fragment;
  if (fragment.startsWith('/') && !_looksLikeOAuthFragment(fragment)) {
    final cleaned = fragment.split('?').first;
    return cleaned.isEmpty ? '/' : cleaned;
  }
  return uri.path;
}

bool _looksLikeOAuthFragment(String fragment) {
  final lower = fragment.toLowerCase();
  return lower.contains('access_token') ||
      lower.contains('refresh_token') ||
      lower.contains('token_type') ||
      lower.contains('code=');
}
