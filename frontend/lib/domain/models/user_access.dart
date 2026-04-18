import 'package:aveli/data/models/profile.dart';
import 'package:aveli/domain/models/entry_state.dart';

class UserAccessState {
  const UserAccessState({
    required this.profile,
    required this.effectiveProfile,
    this.entryState,
  });

  final Profile? profile;
  final Profile? effectiveProfile;
  final EntryState? entryState;

  bool get canEnterApp => entryState?.canEnterApp ?? false;
  bool get isAuthenticated => canEnterApp;

  bool get isAdmin => entryState?.role == 'admin';
  UserRole get role => parseUserRole(entryState?.role);
  bool get isTeacher => entryState?.role == 'teacher';
  bool get isProfessional => false;

  UserAccessState copyWith({
    Profile? profile,
    Profile? effectiveProfile,
    EntryState? entryState,
  }) {
    return UserAccessState(
      profile: profile ?? this.profile,
      effectiveProfile: effectiveProfile ?? this.effectiveProfile,
      entryState: entryState ?? this.entryState,
    );
  }

  static const UserAccessState unauthenticated = UserAccessState(
    profile: null,
    effectiveProfile: null,
  );
}
