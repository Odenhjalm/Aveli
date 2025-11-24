import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/core/auth/auth_controller.dart';
import 'package:wisdom/domain/models/user_access.dart';

final userAccessProvider = Provider<UserAccessState>((ref) {
  final authState = ref.watch(authControllerProvider);
  final profile = authState.profile;
  final claims = authState.claims;
  if (profile == null && claims == null) {
    return UserAccessState.unauthenticated;
  }

  return UserAccessState(
    profile: profile,
    effectiveProfile: profile,
    approval: TeacherApprovalInfo.empty,
    application: null,
    claims: claims,
  );
});
