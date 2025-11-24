import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/core/auth/auth_controller.dart';
import 'package:wisdom/features/auth/application/user_access_provider.dart';

@immutable
class RouteSessionSnapshot {
  const RouteSessionSnapshot({
    required this.isAuthenticated,
    required this.isTeacher,
    required this.isAdmin,
  });

  final bool isAuthenticated;
  final bool isTeacher;
  final bool isAdmin;
}

final routeSessionSnapshotProvider = Provider<RouteSessionSnapshot>((ref) {
  final authState = ref.watch(authControllerProvider);
  final access = ref.watch(userAccessProvider);
  return RouteSessionSnapshot(
    isAuthenticated: authState.isAuthenticated,
    isTeacher: access.isTeacher,
    isAdmin: access.isAdmin,
  );
});
