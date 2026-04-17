import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'profile.g.dart';

enum UserRole { learner, teacher }

abstract final class OnboardingStateValue {
  static const incomplete = 'incomplete';
  static const welcomePending = 'welcome_pending';
  static const completed = 'completed';
}

UserRole parseUserRole(String? value) {
  switch (value) {
    case 'teacher':
      return UserRole.teacher;
    default:
      return UserRole.learner;
  }
}

@JsonSerializable(fieldRename: FieldRename.snake)
class Profile extends Equatable {
  const Profile({
    required this.id,
    required this.email,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      photoUrl: photoUrl ?? this.photoUrl,
      avatarMediaId: avatarMediaId ?? this.avatarMediaId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    email,
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
}
