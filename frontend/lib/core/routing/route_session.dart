import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/domain/models/entry_state.dart';

@immutable
class RouteSessionSnapshot {
  const RouteSessionSnapshot({
    required this.entryState,
    required this.isEntryStateLoading,
  });

  final EntryState? entryState;
  final bool isEntryStateLoading;

  bool get hasEntryState => entryState != null;
  bool get canEnterApp => entryState?.canEnterApp ?? false;
  bool get isAuthenticated => canEnterApp;
  String? get onboardingState => entryState?.onboardingState;
  bool get needsPayment => entryState?.needsPayment ?? false;
  bool get needsOnboarding => entryState?.needsOnboarding ?? false;
  bool get needsWelcome => onboardingState == 'welcome_pending';
  bool get needsCreateProfile =>
      needsOnboarding && onboardingState != 'welcome_pending';
}

final routeSessionSnapshotProvider = Provider<RouteSessionSnapshot>((ref) {
  final authState = ref.watch(authControllerProvider);
  return RouteSessionSnapshot(
    entryState: authState.entryState,
    isEntryStateLoading: authState.isLoading,
  );
});
