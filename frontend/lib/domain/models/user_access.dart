import 'package:aveli/data/models/profile.dart';

class UserAccessState {
  const UserAccessState({
    required this.profile,
    required this.effectiveProfile,
  });

  final Profile? profile;
  final Profile? effectiveProfile;

  bool get isAuthenticated => effectiveProfile != null;

  // Frontend must not derive role/admin authority from JWT claims.
  bool get isAdmin => false;
  UserRole get role => UserRole.learner;
  bool get isTeacher => false;
  bool get isProfessional => false;

  UserAccessState copyWith({Profile? profile, Profile? effectiveProfile}) {
    return UserAccessState(
      profile: profile ?? this.profile,
      effectiveProfile: effectiveProfile ?? this.effectiveProfile,
    );
  }

  static const UserAccessState unauthenticated = UserAccessState(
    profile: null,
    effectiveProfile: null,
  );
}
