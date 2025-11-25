import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'community_post.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class CommunityPost extends Equatable {
  const CommunityPost({
    required this.id,
    required this.authorId,
    required this.content,
    required this.createdAt,
    this.mediaPaths = const <String>[],
    this.profile,
  });

  factory CommunityPost.fromJson(Map<String, dynamic> json) =>
      _$CommunityPostFromJson(json);

  Map<String, dynamic> toJson() => _$CommunityPostToJson(this);

  final String id;
  final String authorId;
  final String content;

  @JsonKey(fromJson: parseDateTime, toJson: dateTimeToIsoString)
  final DateTime createdAt;

  @JsonKey(defaultValue: <String>[])
  final List<String> mediaPaths;

  final CommunityProfile? profile;

  CommunityPost copyWith({CommunityProfile? profile}) {
    return CommunityPost(
      id: id,
      authorId: authorId,
      content: content,
      createdAt: createdAt,
      mediaPaths: mediaPaths,
      profile: profile ?? this.profile,
    );
  }

  @override
  List<Object?> get props => [
    id,
    authorId,
    content,
    createdAt,
    mediaPaths,
    profile,
  ];
}

@JsonSerializable(fieldRename: FieldRename.snake)
class CommunityProfile extends Equatable {
  const CommunityProfile({
    required this.userId,
    this.displayName,
    this.photoUrl,
  });

  factory CommunityProfile.fromJson(Map<String, dynamic> json) =>
      _$CommunityProfileFromJson(json);

  Map<String, dynamic> toJson() => _$CommunityProfileToJson(this);

  final String userId;
  final String? displayName;
  final String? photoUrl;

  @override
  List<Object?> get props => [userId, displayName, photoUrl];
}
