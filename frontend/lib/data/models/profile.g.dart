// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Profile _$ProfileFromJson(Map<String, dynamic> json) => Profile(
  id: Profile._readId(json, 'user_id') as String,
  email: json['email'] as String,
  createdAt: parseDateTime(json['created_at']),
  updatedAt: parseDateTime(json['updated_at']),
  displayName: json['display_name'] as String?,
  bio: json['bio'] as String?,
  photoUrl: json['photo_url'] as String?,
  avatarMediaId: json['avatar_media_id'] as String?,
);

Map<String, dynamic> _$ProfileToJson(Profile instance) => <String, dynamic>{
  'user_id': instance.id,
  'email': instance.email,
  'display_name': instance.displayName,
  'bio': instance.bio,
  'photo_url': instance.photoUrl,
  'avatar_media_id': instance.avatarMediaId,
  'created_at': dateTimeToIsoString(instance.createdAt),
  'updated_at': dateTimeToIsoString(instance.updatedAt),
};
