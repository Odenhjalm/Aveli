import 'package:flutter/foundation.dart';

import 'package:aveli/shared/utils/course_cover_contract.dart';

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  throw StateError('Missing required field: $key');
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw StateError('Missing required bool field: $key');
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw StateError('Missing required int field: $key');
}

@immutable
class CourseCore {
  const CourseCore({
    required this.id,
    required this.title,
    required this.slug,
    required this.courseGroupId,
    required this.step,
    required this.dripEnabled,
    required this.dripIntervalDays,
    required this.coverMediaId,
  });

  final String id;
  final String title;
  final String slug;
  final String? courseGroupId;
  final int? step;
  final bool dripEnabled;
  final int? dripIntervalDays;
  final String? coverMediaId;
}

@immutable
class CourseStudio extends CourseCore {
  const CourseStudio({
    required super.id,
    required super.title,
    required super.slug,
    required super.courseGroupId,
    required super.step,
    required super.dripEnabled,
    required super.dripIntervalDays,
    required super.coverMediaId,
  });

  factory CourseStudio.fromJson(Map<String, dynamic> json) {
    return CourseStudio(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      slug: _requiredString(json, 'slug'),
      courseGroupId: _optionalString(json, 'course_group_id'),
      step: _optionalInt(json, 'step'),
      dripEnabled: _requiredBool(json, 'drip_enabled'),
      dripIntervalDays: _optionalInt(json, 'drip_interval_days'),
      coverMediaId: _optionalString(json, 'cover_media_id'),
    );
  }

  CourseStudio copyWith({
    String? id,
    String? title,
    String? slug,
    String? courseGroupId,
    int? step,
    bool? dripEnabled,
    int? dripIntervalDays,
    String? coverMediaId,
    bool clearCourseGroupId = false,
    bool clearStep = false,
    bool clearDripIntervalDays = false,
    bool clearCoverMediaId = false,
  }) {
    return CourseStudio(
      id: id ?? this.id,
      title: title ?? this.title,
      slug: slug ?? this.slug,
      courseGroupId: clearCourseGroupId
          ? null
          : (courseGroupId ?? this.courseGroupId),
      step: clearStep ? null : (step ?? this.step),
      dripEnabled: dripEnabled ?? this.dripEnabled,
      dripIntervalDays: clearDripIntervalDays
          ? null
          : (dripIntervalDays ?? this.dripIntervalDays),
      coverMediaId: clearCoverMediaId
          ? null
          : (coverMediaId ?? this.coverMediaId),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'slug': slug,
    'course_group_id': courseGroupId,
    'step': step,
    'drip_enabled': dripEnabled,
    'drip_interval_days': dripIntervalDays,
    'cover_media_id': coverMediaId,
  };
}

@immutable
class StudioCourseDetails {
  const StudioCourseDetails({
    required this.course,
    required this.priceAmountCents,
    required this.isPublished,
    required this.cover,
  });

  final CourseStudio course;
  final int? priceAmountCents;
  final bool isPublished;
  final CourseCoverData? cover;

  factory StudioCourseDetails.fromJson(Map<String, dynamic> json) {
    final coverJson = json['cover'];
    final normalizedCover = coverJson is Map<String, dynamic>
        ? CourseCoverData.fromJson(coverJson)
        : coverJson is Map
        ? CourseCoverData.fromJson(Map<String, dynamic>.from(coverJson))
        : null;
    return StudioCourseDetails(
      course: CourseStudio.fromJson(json),
      priceAmountCents:
          _optionalInt(json, 'price_amount_cents') ??
          _optionalInt(json, 'price_cents'),
      isPublished: json['is_published'] == true,
      cover: normalizedCover,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    ...course.toJson(),
    'price_amount_cents': priceAmountCents,
    'is_published': isPublished,
    if (cover != null) 'cover': cover!.toJson(),
  };
}

@immutable
class LessonStudio {
  const LessonStudio({
    required this.id,
    required this.courseId,
    required this.lessonTitle,
    required this.position,
    required this.contentMarkdown,
  });

  final String id;
  final String courseId;
  final String lessonTitle;
  final int position;
  final String? contentMarkdown;

  factory LessonStudio.fromJson(Map<String, dynamic> json) {
    return LessonStudio(
      id: _requiredString(json, 'id'),
      courseId: _requiredString(json, 'course_id'),
      lessonTitle: _requiredString(json, 'lesson_title'),
      position: _optionalInt(json, 'position') ?? 0,
      contentMarkdown: _optionalString(json, 'content_markdown'),
    );
  }

  LessonStudio copyWith({
    String? id,
    String? courseId,
    String? lessonTitle,
    int? position,
    String? contentMarkdown,
    bool clearContentMarkdown = false,
  }) {
    return LessonStudio(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      lessonTitle: lessonTitle ?? this.lessonTitle,
      position: position ?? this.position,
      contentMarkdown: clearContentMarkdown
          ? null
          : (contentMarkdown ?? this.contentMarkdown),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'course_id': courseId,
    'lesson_title': lessonTitle,
    'position': position,
    'content_markdown': contentMarkdown,
  };
}

@immutable
class StudioLessonMediaItem {
  const StudioLessonMediaItem({
    required this.lessonMediaId,
    required this.lessonId,
    required this.position,
    required this.mediaType,
    required this.state,
    required this.previewReady,
    this.mediaAssetId,
    this.originalName,
  });

  final String lessonMediaId;
  final String lessonId;
  final int position;
  final String mediaType;
  final String state;
  final bool previewReady;
  final String? mediaAssetId;
  final String? originalName;

  factory StudioLessonMediaItem.fromJson(Map<String, dynamic> json) {
    return StudioLessonMediaItem(
      lessonMediaId: _requiredString(json, 'lesson_media_id'),
      lessonId: _requiredString(json, 'lesson_id'),
      position: _requiredInt(json, 'position'),
      mediaType: _requiredString(json, 'media_type'),
      state: _requiredString(json, 'state'),
      previewReady: _requiredBool(json, 'preview_ready'),
      mediaAssetId: _optionalString(json, 'media_asset_id'),
      originalName: _optionalString(json, 'original_name'),
    );
  }

  StudioLessonMediaItem copyWith({
    String? lessonMediaId,
    String? lessonId,
    int? position,
    String? mediaType,
    String? state,
    bool? previewReady,
    String? mediaAssetId,
    String? originalName,
    bool clearMediaAssetId = false,
    bool clearOriginalName = false,
  }) {
    return StudioLessonMediaItem(
      lessonMediaId: lessonMediaId ?? this.lessonMediaId,
      lessonId: lessonId ?? this.lessonId,
      position: position ?? this.position,
      mediaType: mediaType ?? this.mediaType,
      state: state ?? this.state,
      previewReady: previewReady ?? this.previewReady,
      mediaAssetId: clearMediaAssetId
          ? null
          : (mediaAssetId ?? this.mediaAssetId),
      originalName: clearOriginalName
          ? null
          : (originalName ?? this.originalName),
    );
  }
}

@immutable
class StudioLessonMediaUploadTarget {
  const StudioLessonMediaUploadTarget({
    required this.lessonMediaId,
    required this.lessonId,
    required this.mediaType,
    required this.state,
    required this.position,
    required this.uploadUrl,
    required this.headers,
    required this.expiresAt,
  });

  final String lessonMediaId;
  final String lessonId;
  final String mediaType;
  final String state;
  final int position;
  final String uploadUrl;
  final Map<String, String> headers;
  final DateTime expiresAt;

  factory StudioLessonMediaUploadTarget.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'];
    final headers = rawHeaders is Map
        ? rawHeaders.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          )
        : const <String, String>{};
    final expiresAtValue = json['expires_at'];
    if (expiresAtValue is! String || expiresAtValue.trim().isEmpty) {
      throw StateError('Missing required field: expires_at');
    }
    return StudioLessonMediaUploadTarget(
      lessonMediaId: _requiredString(json, 'lesson_media_id'),
      lessonId: _requiredString(json, 'lesson_id'),
      mediaType: _requiredString(json, 'media_type'),
      state: _requiredString(json, 'state'),
      position: _requiredInt(json, 'position'),
      uploadUrl: _requiredString(json, 'upload_url'),
      headers: headers,
      expiresAt: DateTime.parse(expiresAtValue).toUtc(),
    );
  }
}

@immutable
class StudioLessonMediaPreviewItem {
  const StudioLessonMediaPreviewItem({
    required this.lessonMediaId,
    required this.mediaType,
    required this.authoritativeEditorReady,
    this.previewUrl,
    this.durationSeconds,
    this.fileName,
    this.failureReason,
  });

  final String lessonMediaId;
  final String mediaType;
  final bool authoritativeEditorReady;
  final String? previewUrl;
  final int? durationSeconds;
  final String? fileName;
  final String? failureReason;

  factory StudioLessonMediaPreviewItem.fromJson(
    String lessonMediaId,
    Map<String, dynamic> json,
  ) {
    return StudioLessonMediaPreviewItem(
      lessonMediaId: lessonMediaId,
      mediaType: _requiredString(json, 'media_type'),
      authoritativeEditorReady: _requiredBool(
        json,
        'authoritative_editor_ready',
      ),
      previewUrl: _optionalString(json, 'resolved_preview_url'),
      durationSeconds: _optionalInt(json, 'duration_seconds'),
      fileName: _optionalString(json, 'file_name'),
      failureReason: _optionalString(json, 'failure_reason'),
    );
  }
}
