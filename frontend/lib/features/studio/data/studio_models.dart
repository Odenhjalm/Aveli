import 'package:flutter/foundation.dart';

import 'package:aveli/shared/models/request_headers.dart';
import 'package:aveli/shared/utils/course_cover_contract.dart';

Object? _requireResponseField(Object? payload, String key, String label) {
  switch (payload) {
    case final Map data when data.containsKey(key):
      return data[key];
    case final Map _:
      throw StateError('$label is missing required field: $key');
    default:
      throw StateError('$label returned a non-object payload');
  }
}

String _requiredResponseString(Object? payload, String key, String label) {
  final value = _requireResponseField(payload, key, label);
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw StateError('$label field "$key" must be a non-empty string');
}

String _requiredResponseStringValue(Object? payload, String key, String label) {
  final value = _requireResponseField(payload, key, label);
  if (value is String) {
    return value;
  }
  throw StateError('$label field "$key" must be a string');
}

String? _nullableResponseString(Object? payload, String key, String label) {
  final value = _requireResponseField(payload, key, label);
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw StateError('$label field "$key" must be a string or null');
}

int _requiredResponseInt(Object? payload, String key, String label) {
  final value = _requireResponseField(payload, key, label);
  if (value is int) {
    return value;
  }
  throw StateError('$label field "$key" must be an int');
}

int? _nullableResponseInt(Object? payload, String key, String label) {
  final value = _requireResponseField(payload, key, label);
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  throw StateError('$label field "$key" must be an int or null');
}

bool _requiredResponseBool(Object? payload, String key, String label) {
  final value = _requireResponseField(payload, key, label);
  if (value is bool) {
    return value;
  }
  throw StateError('$label field "$key" must be a bool');
}

RequestHeaders _requiredResponseHeaders(
  Object? payload,
  String key,
  String label,
) {
  return RequestHeaders.fromResponseObject(
    _requireResponseField(payload, key, label),
    label: '$label field "$key"',
  );
}

DateTime _requiredResponseUtcDateTime(
  Object? payload,
  String key,
  String label,
) {
  final value = _requireResponseField(payload, key, label);
  if (value is! String || value.isEmpty) {
    throw StateError('$label field "$key" must be an ISO datetime string');
  }
  return DateTime.parse(value);
}

CourseCoverData? _nullableResponseCourseCover(
  Object? payload,
  String key,
  String label,
) {
  final value = _requireResponseField(payload, key, label);
  if (value == null) {
    return null;
  }
  return CourseCoverData(
    mediaId: _nullableResponseString(value, 'media_id', '$label field "$key"'),
    state: _requiredResponseString(value, 'state', '$label field "$key"'),
    resolvedUrl: _nullableResponseString(
      value,
      'resolved_url',
      '$label field "$key"',
    ),
    source: _requiredResponseString(value, 'source', '$label field "$key"'),
  );
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
  final String courseGroupId;
  final String step;
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
    required this.priceAmountCents,
    required this.cover,
  });

  final int? priceAmountCents;
  final CourseCoverData? cover;

  factory CourseStudio.fromResponse(
    Object? payload, {
    String label = 'Course',
  }) {
    return CourseStudio(
      id: _requiredResponseString(payload, 'id', label),
      title: _requiredResponseString(payload, 'title', label),
      slug: _requiredResponseString(payload, 'slug', label),
      courseGroupId: _requiredResponseString(payload, 'course_group_id', label),
      step: _requiredResponseStringValue(payload, 'step', label),
      dripEnabled: _requiredResponseBool(payload, 'drip_enabled', label),
      dripIntervalDays: _nullableResponseInt(
        payload,
        'drip_interval_days',
        label,
      ),
      coverMediaId: _nullableResponseString(payload, 'cover_media_id', label),
      priceAmountCents: _nullableResponseInt(
        payload,
        'price_amount_cents',
        label,
      ),
      cover: _nullableResponseCourseCover(payload, 'cover', label),
    );
  }

  CourseStudio copyWith({
    String? id,
    String? title,
    String? slug,
    String? courseGroupId,
    String? step,
    bool? dripEnabled,
    int? dripIntervalDays,
    String? coverMediaId,
    int? priceAmountCents,
    CourseCoverData? cover,
    bool clearCourseGroupId = false,
    bool clearDripIntervalDays = false,
    bool clearCoverMediaId = false,
    bool clearPriceAmountCents = false,
    bool clearCover = false,
  }) {
    return CourseStudio(
      id: id != null ? id : this.id,
      title: title != null ? title : this.title,
      slug: slug != null ? slug : this.slug,
      courseGroupId: clearCourseGroupId
          ? ''
          : (courseGroupId != null ? courseGroupId : this.courseGroupId),
      step: step != null ? step : this.step,
      dripEnabled: dripEnabled != null ? dripEnabled : this.dripEnabled,
      dripIntervalDays: clearDripIntervalDays
          ? null
          : (dripIntervalDays != null
                ? dripIntervalDays
                : this.dripIntervalDays),
      coverMediaId: clearCoverMediaId
          ? null
          : (coverMediaId != null ? coverMediaId : this.coverMediaId),
      priceAmountCents: clearPriceAmountCents
          ? null
          : (priceAmountCents != null
                ? priceAmountCents
                : this.priceAmountCents),
      cover: clearCover ? null : (cover != null ? cover : this.cover),
    );
  }
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

  factory LessonStudio.fromResponse(
    Object? payload, {
    String label = 'StudioLesson',
  }) {
    return LessonStudio(
      id: _requiredResponseString(payload, 'id', label),
      courseId: _requiredResponseString(payload, 'course_id', label),
      lessonTitle: _requiredResponseString(payload, 'lesson_title', label),
      position: _requiredResponseInt(payload, 'position', label),
      contentMarkdown: _requiredResponseStringValue(
        payload,
        'content_markdown',
        label,
      ),
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
      id: id != null ? id : this.id,
      courseId: courseId != null ? courseId : this.courseId,
      lessonTitle: lessonTitle != null ? lessonTitle : this.lessonTitle,
      position: position != null ? position : this.position,
      contentMarkdown: clearContentMarkdown
          ? null
          : (contentMarkdown != null ? contentMarkdown : this.contentMarkdown),
    );
  }
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

  factory StudioLessonMediaItem.fromResponse(Object? payload) {
    return StudioLessonMediaItem(
      lessonMediaId: _requiredResponseString(
        payload,
        'lesson_media_id',
        'StudioLessonMediaItem',
      ),
      lessonId: _requiredResponseString(
        payload,
        'lesson_id',
        'StudioLessonMediaItem',
      ),
      position: _requiredResponseInt(
        payload,
        'position',
        'StudioLessonMediaItem',
      ),
      mediaType: _requiredResponseString(
        payload,
        'media_type',
        'StudioLessonMediaItem',
      ),
      state: _requiredResponseString(payload, 'state', 'StudioLessonMediaItem'),
      previewReady: _requiredResponseBool(
        payload,
        'preview_ready',
        'StudioLessonMediaItem',
      ),
      mediaAssetId: _nullableResponseString(
        payload,
        'media_asset_id',
        'StudioLessonMediaItem',
      ),
      originalName: _nullableResponseString(
        payload,
        'original_name',
        'StudioLessonMediaItem',
      ),
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
      lessonMediaId: lessonMediaId != null ? lessonMediaId : this.lessonMediaId,
      lessonId: lessonId != null ? lessonId : this.lessonId,
      position: position != null ? position : this.position,
      mediaType: mediaType != null ? mediaType : this.mediaType,
      state: state != null ? state : this.state,
      previewReady: previewReady != null ? previewReady : this.previewReady,
      mediaAssetId: clearMediaAssetId
          ? null
          : (mediaAssetId != null ? mediaAssetId : this.mediaAssetId),
      originalName: clearOriginalName
          ? null
          : (originalName != null ? originalName : this.originalName),
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
  final RequestHeaders headers;
  final DateTime expiresAt;

  factory StudioLessonMediaUploadTarget.fromResponse(Object? payload) {
    return StudioLessonMediaUploadTarget(
      lessonMediaId: _requiredResponseString(
        payload,
        'lesson_media_id',
        'StudioLessonMediaUploadTarget',
      ),
      lessonId: _requiredResponseString(
        payload,
        'lesson_id',
        'StudioLessonMediaUploadTarget',
      ),
      mediaType: _requiredResponseString(
        payload,
        'media_type',
        'StudioLessonMediaUploadTarget',
      ),
      state: _requiredResponseString(
        payload,
        'state',
        'StudioLessonMediaUploadTarget',
      ),
      position: _requiredResponseInt(
        payload,
        'position',
        'StudioLessonMediaUploadTarget',
      ),
      uploadUrl: _requiredResponseString(
        payload,
        'upload_url',
        'StudioLessonMediaUploadTarget',
      ),
      headers: _requiredResponseHeaders(
        payload,
        'headers',
        'StudioLessonMediaUploadTarget',
      ),
      expiresAt: _requiredResponseUtcDateTime(
        payload,
        'expires_at',
        'StudioLessonMediaUploadTarget',
      ),
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

  factory StudioLessonMediaPreviewItem.fromResponse(
    String lessonMediaId,
    Object? payload,
  ) {
    return StudioLessonMediaPreviewItem(
      lessonMediaId: lessonMediaId,
      mediaType: _requiredResponseString(
        payload,
        'media_type',
        'StudioLessonMediaPreviewItem',
      ),
      authoritativeEditorReady: _requiredResponseBool(
        payload,
        'authoritative_editor_ready',
        'StudioLessonMediaPreviewItem',
      ),
      previewUrl: _nullableResponseString(
        payload,
        'resolved_preview_url',
        'StudioLessonMediaPreviewItem',
      ),
      durationSeconds: _nullableResponseInt(
        payload,
        'duration_seconds',
        'StudioLessonMediaPreviewItem',
      ),
      fileName: _nullableResponseString(
        payload,
        'file_name',
        'StudioLessonMediaPreviewItem',
      ),
      failureReason: _nullableResponseString(
        payload,
        'failure_reason',
        'StudioLessonMediaPreviewItem',
      ),
    );
  }
}

@immutable
class StudioLessonMediaPreviewBatch {
  StudioLessonMediaPreviewBatch({
    required List<StudioLessonMediaPreviewItem> items,
  }) : items = List<StudioLessonMediaPreviewItem>.unmodifiable(items);

  final List<StudioLessonMediaPreviewItem> items;

  bool get isEmpty => items.isEmpty;

  StudioLessonMediaPreviewItem? itemFor(String lessonMediaId) {
    for (final item in items) {
      if (item.lessonMediaId == lessonMediaId) {
        return item;
      }
    }
    return null;
  }
}
