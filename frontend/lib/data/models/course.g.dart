// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'course.dart';

// ************************************************************************
// JsonSerializableGenerator
// ************************************************************************

Course _$CourseFromJson(Map<String, dynamic> json) => Course(
  id: json['id'] as String,
  slug: json['slug'] as String?,
  title: json['title'] as String,
  description: json['description'] as String?,
  coverUrl: json['cover_url'] as String?,
  coverMediaId: json['cover_media_id'] as String?,
  videoUrl: json['video_url'] as String?,
  isFreeIntro: json['is_free_intro'] as bool? ?? false,
  isPublished: json['is_published'] as bool? ?? false,
);

Map<String, dynamic> _$CourseToJson(Course instance) => <String, dynamic>{
  'id': instance.id,
  'slug': instance.slug,
  'title': instance.title,
  'description': instance.description,
  'cover_url': instance.coverUrl,
  'cover_media_id': instance.coverMediaId,
  'video_url': instance.videoUrl,
  'is_free_intro': instance.isFreeIntro,
  'is_published': instance.isPublished,
};
