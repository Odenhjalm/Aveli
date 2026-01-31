import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/features/auth/application/user_access_provider.dart';

@immutable
class RouteSessionSnapshot {
  const RouteSessionSnapshot({
    required this.isAuthenticated,
    required this.isAuthLoading,
    required this.hasTentativeSession,
    required this.isTeacher,
    required this.isAdmin,
  });

  final bool isAuthenticated;
  final bool isAuthLoading;
  final bool hasTentativeSession;
  final bool isTeacher;
  final bool isAdmin;
}

final routeSessionSnapshotProvider = Provider<RouteSessionSnapshot>((ref) {
  final authState = ref.watch(authControllerProvider);
  final access = ref.watch(userAccessProvider);
  return RouteSessionSnapshot(
    isAuthenticated: authState.profile != null,
    isAuthLoading: authState.isLoading,
    hasTentativeSession: authState.claims != null,
    isTeacher: access.isTeacher,
    isAdmin: access.isAdmin,
  );
});
