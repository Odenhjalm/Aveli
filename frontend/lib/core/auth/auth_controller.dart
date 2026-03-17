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
import 'package:aveli/features/onboarding/data/onboarding_repository.dart';
import 'package:aveli/features/onboarding/domain/onboarding_status.dart';
import 'package:aveli/gate.dart';

@immutable
class AuthState {
  const AuthState({
    this.profile,
    this.claims,
    this.onboarding,
    this.isLoading = false,
    this.error,
    this.verificationEmailStatus,
  });

  final Profile? profile;
  final AuthClaims? claims;
  final OnboardingStatus? onboarding;
  final bool isLoading;
  final String? error;
  final String? verificationEmailStatus;

  AuthState copyWith({
    Profile? profile,
    AuthClaims? claims,
    OnboardingStatus? onboarding,
    bool? isLoading,
    String? error,
    String? verificationEmailStatus,
    bool clearClaims = false,
    bool clearOnboarding = false,
  }) => AuthState(
    profile: profile ?? this.profile,
    claims: clearClaims ? null : (claims ?? this.claims),
    onboarding: clearOnboarding ? null : (onboarding ?? this.onboarding),
    isLoading: isLoading ?? this.isLoading,
    error: error,
    verificationEmailStatus:
        verificationEmailStatus ?? this.verificationEmailStatus,
  );

  /// Verified auth: JWT claims alone are *not* sufficient.
  bool get isAuthenticated => profile != null;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repo, this._authObserver, [this._onboardingRepo])
    : super(const AuthState()) {
    _authSub = _authObserver.events.listen(_handleAuthEvent);
  }

  final AuthRepository _repo;
  final AuthHttpObserver _authObserver;
  final OnboardingRepository? _onboardingRepo;
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

    await _hydrateProfileAndOnboarding();
  }

  Future<void> hydrateProfile() async {
    if (state.profile != null || state.isLoading) return;
    await _hydrateProfileAndOnboarding();
  }

  Future<void> _hydrateProfileAndOnboarding() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final profile = await _repo.getCurrentProfile();
      final onboarding = await _fetchOnboarding();
      state = state.copyWith(
        profile: profile,
        onboarding: onboarding,
        isLoading: false,
      );
      gate.allow();
    } catch (err, stackTrace) {
      await _repo.logout();
      gate.reset();
      final failure = AppFailure.from(err, stackTrace);
      state = AuthState(
        profile: null,
        claims: null,
        onboarding: null,
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
      final onboarding = await _fetchOnboarding();
      state = AuthState(
        profile: profile,
        claims: claims,
        onboarding: onboarding,
        isLoading: false,
      );
      gate.allow();
    } catch (err, stackTrace) {
      final failure = AppFailure.from(err, stackTrace);
      state = AuthState(
        profile: null,
        claims: null,
        onboarding: null,
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
      final result = await _repo.register(
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
      final onboarding = await _fetchOnboarding();
      state = AuthState(
        profile: result.profile,
        claims: claims,
        onboarding: onboarding,
        isLoading: false,
        verificationEmailStatus: result.verificationEmailStatus,
      );
      gate.allow();
    } catch (err, stackTrace) {
      final failure = AppFailure.from(err, stackTrace);
      state = AuthState(
        profile: null,
        claims: null,
        onboarding: null,
        isLoading: false,
        error: failure.message,
      );
      gate.reset();
      throw failure;
    }
  }

  Future<void> refreshOnboarding() async {
    if (state.profile == null || _onboardingRepo == null) return;
    try {
      final onboarding = await _fetchOnboarding();
      state = state.copyWith(onboarding: onboarding, error: null);
    } catch (_) {
      // Keep the last known onboarding snapshot when refresh fails.
    }
  }

  Future<OnboardingStatus?> _fetchOnboarding() async {
    final onboardingRepo = _onboardingRepo;
    if (onboardingRepo == null) {
      return null;
    }
    return onboardingRepo.getMe();
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
    final onboardingRepo = ref.watch(onboardingRepositoryProvider);
    final observer = ref.watch(authHttpObserverProvider);
    final controller = AuthController(repo, observer, onboardingRepo);
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
