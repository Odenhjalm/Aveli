import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/auth/auth_controller.dart';

@immutable
class RouteSessionSnapshot {
  const RouteSessionSnapshot({
    required this.isAuthenticated,
    required this.isAuthLoading,
    required this.hasTentativeSession,
  });

  final bool isAuthenticated;
  final bool isAuthLoading;
  final bool hasTentativeSession;
}

final routeSessionSnapshotProvider = Provider<RouteSessionSnapshot>((ref) {
  final authState = ref.watch(authControllerProvider);
  return RouteSessionSnapshot(
    isAuthenticated: authState.profile != null,
    isAuthLoading: authState.isLoading,
    hasTentativeSession: authState.hasStoredToken && authState.profile == null,
  );
});
