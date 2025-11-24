// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'community_post.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CommunityPost _$CommunityPostFromJson(Map<String, dynamic> json) =>
    CommunityPost(
      id: json['id'] as String,
      authorId: json['author_id'] as String,
      content: json['content'] as String,
      createdAt: parseDateTime(json['created_at']),
      mediaPaths:
          (json['media_paths'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      profile: json['profile'] == null
          ? null
          : CommunityProfile.fromJson(json['profile'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$CommunityPostToJson(CommunityPost instance) =>
    <String, dynamic>{
      'id': instance.id,
      'author_id': instance.authorId,
      'content': instance.content,
      'created_at': dateTimeToIsoString(instance.createdAt),
      'media_paths': instance.mediaPaths,
      'profile': instance.profile?.toJson(),
    };

CommunityProfile _$CommunityProfileFromJson(Map<String, dynamic> json) =>
    CommunityProfile(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String?,
      photoUrl: json['photo_url'] as String?,
    );

Map<String, dynamic> _$CommunityProfileToJson(CommunityProfile instance) =>
    <String, dynamic>{
      'user_id': instance.userId,
      'display_name': instance.displayName,
      'photo_url': instance.photoUrl,
    };
