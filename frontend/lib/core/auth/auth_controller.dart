import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/domain/models/entry_state.dart';
import 'package:aveli/features/auth/data/entry_state_repository.dart';
import 'package:aveli/gate.dart';

@immutable
class AuthState {
  const AuthState({
    this.profile,
    this.entryState,
    this.hasStoredToken = false,
    this.isLoading = false,
    this.error,
  });

  final Profile? profile;
  final EntryState? entryState;
  final bool hasStoredToken;
  final bool isLoading;
  final String? error;

  AuthState copyWith({
    Profile? profile,
    EntryState? entryState,
    bool? hasStoredToken,
    bool? isLoading,
    String? error,
    bool clearProfile = false,
    bool clearEntryState = false,
  }) => AuthState(
    profile: clearProfile ? null : (profile ?? this.profile),
    entryState: clearEntryState ? null : (entryState ?? this.entryState),
    hasStoredToken: hasStoredToken ?? this.hasStoredToken,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );

  bool get canEnterApp => entryState?.canEnterApp ?? false;
  bool get isAuthenticated => canEnterApp;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(
    this._repo,
    this._authObserver, {
    Future<EntryState> Function()? loadEntryState,
  }) : _loadEntryState = loadEntryState,
       super(const AuthState()) {
    _authSub = _authObserver.events.listen(_handleAuthEvent);
  }

  final AuthRepository _repo;
  final AuthHttpObserver _authObserver;
  final Future<EntryState> Function()? _loadEntryState;
  late final StreamSubscription<AuthHttpEvent> _authSub;

  Future<void> loadSession({bool hydrateProfile = true}) async {
    state = state.copyWith(isLoading: true, error: null);
    final token = await _repo.currentToken();
    if (token == null || token.isEmpty) {
      gate.reset();
      state = const AuthState();
      return;
    }

    state = state.copyWith(
      hasStoredToken: true,
      isLoading: true,
      error: null,
      clearEntryState: true,
    );

    final entryState = await _fetchEntryState();
    state = state.copyWith(
      entryState: entryState,
      hasStoredToken: true,
      isLoading: false,
    );
    gate.reset();

    if (hydrateProfile) {
      await _hydrateProfile();
    }
  }

  Future<void> hydrateProfile() async {
    if (state.profile != null && state.entryState != null) return;
    await _hydrateProfile();
  }

  Future<void> _hydrateProfile() async {
    try {
      final profile = await _repo.getCurrentProfile();
      state = state.copyWith(
        profile: profile,
        hasStoredToken: true,
        error: null,
      );
      gate.reset();
    } catch (err, stackTrace) {
      gate.reset();
      final failure = AppFailure.from(err, stackTrace);
      state = state.copyWith(error: failure.message);
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      hasStoredToken: false,
      clearProfile: true,
      clearEntryState: true,
    );
    try {
      final profile = await _repo.login(email: email, password: password);
      final entryState = await _fetchEntryState();
      state = AuthState(
        profile: profile,
        entryState: entryState,
        hasStoredToken: true,
        isLoading: false,
      );
      gate.reset();
    } catch (err, stackTrace) {
      final failure = AppFailure.from(err, stackTrace);
      state = AuthState(
        profile: null,
        hasStoredToken: false,
        isLoading: false,
        error: failure.message,
      );
      gate.reset();
      throw failure;
    }
  }

  Future<void> register(
    String email,
    String password,
  ) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      hasStoredToken: false,
      clearProfile: true,
      clearEntryState: true,
    );
    try {
      final profile = await _repo.register(
        email: email,
        password: password,
      );
      final entryState = await _fetchEntryState();
      state = AuthState(
        profile: profile,
        entryState: entryState,
        hasStoredToken: true,
        isLoading: false,
      );
      gate.reset();
    } catch (err, stackTrace) {
      final failure = AppFailure.from(err, stackTrace);
      state = AuthState(
        profile: null,
        hasStoredToken: false,
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

  Future<void> createProfile({
    required String displayName,
    String? bio,
    String? referralCode,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final profile = await _repo.createProfile(
        displayName: displayName,
        bio: bio,
      );
      final normalizedReferralCode = referralCode?.trim();
      if (normalizedReferralCode != null && normalizedReferralCode.isNotEmpty) {
        await _repo.redeemReferral(code: normalizedReferralCode);
      }
      final entryState = await _fetchEntryState();
      state = AuthState(
        profile: profile,
        entryState: entryState,
        hasStoredToken: true,
        isLoading: false,
      );
      gate.reset();
    } catch (err, stackTrace) {
      final failure = AppFailure.from(err, stackTrace);
      state = state.copyWith(isLoading: false, error: failure.message);
      throw failure;
    }
  }

  Future<void> completeWelcome() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final profile = await _repo.completeWelcome();
      final entryState = await _fetchEntryState();
      state = AuthState(
        profile: profile,
        entryState: entryState,
        hasStoredToken: true,
        isLoading: false,
      );
      gate.reset();
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

  Future<EntryState?> _fetchEntryState() async {
    final loader = _loadEntryState;
    if (loader == null) {
      return null;
    }
    return loader();
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
    final entryStateRepo = ref.watch(entryStateRepositoryProvider);
    final controller = AuthController(
      repo,
      observer,
      loadEntryState: entryStateRepo.fetchEntryState,
    );
    controller.loadSession();
    return controller;
  },
);
