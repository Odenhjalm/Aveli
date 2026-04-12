import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/domain/models/entry_state.dart';

@immutable
class RouteSessionSnapshot {
  const RouteSessionSnapshot({
    required this.entryState,
    required this.isEntryStateLoading,
    this.profileDisplayName,
  });

  final EntryState? entryState;
  final bool isEntryStateLoading;
  final String? profileDisplayName;

  bool get hasEntryState => entryState != null;
  bool get canEnterApp => entryState?.canEnterApp ?? false;
  bool get isAuthenticated => canEnterApp;
  bool get needsPayment => entryState?.needsPayment ?? false;
  bool get needsOnboarding => entryState?.needsOnboarding ?? false;
  bool get hasProfileName => profileDisplayName?.trim().isNotEmpty ?? false;
}

final routeSessionSnapshotProvider = Provider<RouteSessionSnapshot>((ref) {
  final authState = ref.watch(authControllerProvider);
  return RouteSessionSnapshot(
    entryState: authState.entryState,
    isEntryStateLoading: authState.isLoading,
    profileDisplayName: authState.profile?.displayName,
  );
});
