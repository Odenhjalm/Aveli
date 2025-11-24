import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'profile.g.dart';

enum UserRole { user, professional, teacher }

UserRole parseUserRole(String? value) {
  switch (value) {
    case 'teacher':
      return UserRole.teacher;
    case 'professional':
      return UserRole.professional;
    default:
      return UserRole.user;
  }
}

@JsonSerializable(fieldRename: FieldRename.snake)
class Profile extends Equatable {
  const Profile({
    required this.id,
    required this.email,
    required this.userRole,
    required this.isAdmin,
    required this.createdAt,
    required this.updatedAt,
    this.displayName,
    this.bio,
    this.photoUrl,
    this.avatarMediaId,
  });

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);

  Map<String, dynamic> toJson() => _$ProfileToJson(this);

  @JsonKey(name: 'user_id', readValue: _readId)
  final String id;

  final String email;

  @JsonKey(name: 'role_v2', readValue: _readUserRole, toJson: _writeUserRole)
  final UserRole userRole;

  @JsonKey(name: 'is_admin')
  final bool isAdmin;

  final String? displayName;
  final String? bio;
  final String? photoUrl;

  @JsonKey(name: 'avatar_media_id')
  final String? avatarMediaId;

  @JsonKey(fromJson: parseDateTime, toJson: dateTimeToIsoString)
  final DateTime createdAt;

  @JsonKey(fromJson: parseDateTime, toJson: dateTimeToIsoString)
  final DateTime updatedAt;

  Profile copyWith({
    String? id,
    String? email,
    UserRole? userRole,
    bool? isAdmin,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? displayName,
    String? bio,
    String? photoUrl,
    String? avatarMediaId,
  }) {
    return Profile(
      id: id ?? this.id,
      email: email ?? this.email,
      userRole: userRole ?? this.userRole,
      isAdmin: isAdmin ?? this.isAdmin,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      photoUrl: photoUrl ?? this.photoUrl,
      avatarMediaId: avatarMediaId ?? this.avatarMediaId,
    );
  }

  bool get isTeacher => userRole == UserRole.teacher;
  bool get isProfessional =>
      userRole == UserRole.professional || userRole == UserRole.teacher;

  @override
  List<Object?> get props => [
    id,
    email,
    userRole,
    isAdmin,
    displayName,
    bio,
    photoUrl,
    avatarMediaId,
    createdAt,
    updatedAt,
  ];

  static String _readId(Map json, String key) {
    final value = json['user_id'] ?? json['id'];
    return value?.toString() ?? '';
  }

  static String _readUserRole(Map json, String key) {
    final legacy = (json['role'] as String?) ?? 'user';
    final userRoleValue = json['role_v2'] as String?;
    final admin = json['is_admin'] == true || legacy == 'admin';
    final role = userRoleValue ?? legacy;
    return admin ? 'teacher' : role;
  }

  static String _writeUserRole(UserRole role) => switch (role) {
    UserRole.teacher => 'teacher',
    UserRole.professional => 'professional',
    UserRole.user => 'user',
  };
}
