import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/domain/models/user_access.dart';

final userAccessProvider = Provider<UserAccessState>((ref) {
  final authState = ref.watch(authControllerProvider);
  return UserAccessState(
    profile: authState.profile,
    effectiveProfile: authState.isAuthenticated ? authState.profile : null,
    entryState: authState.entryState,
  );
});
