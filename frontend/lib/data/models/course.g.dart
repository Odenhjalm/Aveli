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
  coverMediaId: json['cover_media_id'] as String?,
  cover: json['cover'] == null
      ? null
      : CourseCoverData.fromJson(
          Map<String, dynamic>.from(json['cover'] as Map),
        ),
  videoUrl: json['video_url'] as String?,
  isPublished: json['is_published'] as bool? ?? false,
);

Map<String, dynamic> _$CourseToJson(Course instance) => <String, dynamic>{
  'id': instance.id,
  'slug': instance.slug,
  'title': instance.title,
  'description': instance.description,
  'cover_media_id': instance.coverMediaId,
  'cover': instance.cover?.toJson(),
  'video_url': instance.videoUrl,
  'is_published': instance.isPublished,
};
