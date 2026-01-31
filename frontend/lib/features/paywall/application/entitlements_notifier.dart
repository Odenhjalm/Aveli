import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/features/payments/application/billing_providers.dart';
import 'package:aveli/features/payments/data/billing_api.dart';

import '../data/entitlements_api.dart';
import '../domain/entitlements.dart';

class EntitlementsState {
  const EntitlementsState({this.loading = false, this.data, this.error});

  final bool loading;
  final Entitlements? data;
  final Object? error;

  EntitlementsState copyWith({
    bool? loading,
    Entitlements? data,
    Object? error,
    bool clearError = false,
  }) {
    return EntitlementsState(
      loading: loading ?? this.loading,
      data: data ?? this.data,
      error: clearError ? null : error ?? this.error,
    );
  }

  static const initial = EntitlementsState();
}

class EntitlementsNotifier extends StateNotifier<EntitlementsState> {
  EntitlementsNotifier(this._api, this._billingApi)
    : super(EntitlementsState.initial);

  final EntitlementsApi _api;
  final BillingApi _billingApi;

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final entitlements = await _api.fetchEntitlements();
      state = state.copyWith(loading: false, data: entitlements);
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  void reset() {
    state = EntitlementsState.initial;
  }

  bool get membershipActive => state.data?.membership.isActive == true;
  bool hasCourse(String slug) => state.data?.courses.contains(slug) == true;

  Future<void> cancelSubscription() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _billingApi.cancelSubscription();
      state = state.copyWith(loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
      rethrow;
    }
  }
}

final entitlementsApiProvider = Provider<EntitlementsApi>((ref) {
  final tokens = ref.watch(tokenStorageProvider);
  final config = ref.watch(appConfigProvider);
  return EntitlementsApi(tokenStorage: tokens, baseUrl: config.apiBaseUrl);
});

final entitlementsNotifierProvider =
    StateNotifierProvider<EntitlementsNotifier, EntitlementsState>((ref) {
      final api = ref.watch(entitlementsApiProvider);
      final billingApi = ref.watch(billingApiProvider);
      return EntitlementsNotifier(api, billingApi);
    });

/// Keeps entitlements in sync with *verified* auth.
///
/// This avoids optimistic JWT-based auth and prevents retry storms when the user
/// is logged out or auth is still bootstrapping.
final entitlementsAuthSyncProvider = Provider<void>((ref) {
  var disposed = false;
  ref.onDispose(() => disposed = true);

  void schedule(void Function() action) {
    Future.microtask(() {
      if (disposed) return;
      action();
    });
  }

  ref.listen<AuthState>(authControllerProvider, (prev, next) {
    final wasAuthed = prev?.profile != null;
    final isAuthed = next.profile != null;
    if (isAuthed && !wasAuthed) {
      schedule(() => ref.read(entitlementsNotifierProvider.notifier).refresh());
    } else if (!isAuthed && wasAuthed) {
      schedule(() => ref.read(entitlementsNotifierProvider.notifier).reset());
    }
  }, fireImmediately: true);
});
