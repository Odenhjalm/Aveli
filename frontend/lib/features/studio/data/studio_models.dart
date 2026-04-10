import 'package:flutter/foundation.dart';

import 'package:aveli/shared/models/request_headers.dart';
import 'package:aveli/shared/utils/course_cover_contract.dart';
import 'package:aveli/shared/utils/resolved_media_contract.dart';

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

ResolvedMediaData? _nullableResolvedMedia(
  Object? payload,
  String key,
  String label,
) {
  switch (payload) {
    case final Map data when data.containsKey(key):
      final value = data[key];
      if (value == null) {
        return null;
      }
      if (value is Map) {
        return ResolvedMediaData.fromJson(Map<String, dynamic>.from(value));
      }
      throw StateError('$label field "$key" must be an object or null');
    case final Map _:
      return null;
    default:
      throw StateError('$label returned a non-object payload');
  }
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
    required this.cover,
  });

  final String id;
  final String title;
  final String slug;
  final String courseGroupId;
  final String step;
  final bool dripEnabled;
  final int? dripIntervalDays;
  final String? coverMediaId;
  final CourseCoverData? cover;
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
    required super.cover,
    required this.priceAmountCents,
  });

  final int? priceAmountCents;

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
      cover: switch (_requireResponseField(payload, 'cover', label)) {
        null => null,
        final Map<String, dynamic> data => CourseCoverData.fromJson(data),
        final Map data => CourseCoverData.fromJson(
          Map<String, dynamic>.from(data),
        ),
        final Object _ => throw StateError(
          '$label field "cover" must be an object or null',
        ),
      },
      priceAmountCents: _nullableResponseInt(
        payload,
        'price_amount_cents',
        label,
      ),
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
    CourseCoverData? cover,
    int? priceAmountCents,
    bool clearCourseGroupId = false,
    bool clearDripIntervalDays = false,
    bool clearCoverMediaId = false,
    bool clearCover = false,
    bool clearPriceAmountCents = false,
  }) {
    return CourseStudio(
      id: id ?? this.id,
      title: title ?? this.title,
      slug: slug ?? this.slug,
      courseGroupId: clearCourseGroupId
          ? ''
          : (courseGroupId ?? this.courseGroupId),
      step: step ?? this.step,
      dripEnabled: dripEnabled ?? this.dripEnabled,
      dripIntervalDays: clearDripIntervalDays
          ? null
          : (dripIntervalDays ?? this.dripIntervalDays),
      coverMediaId: clearCoverMediaId
          ? null
          : (coverMediaId ?? this.coverMediaId),
      cover: clearCover ? null : (cover ?? this.cover),
      priceAmountCents: clearPriceAmountCents
          ? null
          : (priceAmountCents ?? this.priceAmountCents),
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
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      lessonTitle: lessonTitle ?? this.lessonTitle,
      position: position ?? this.position,
      contentMarkdown: clearContentMarkdown
          ? null
          : (contentMarkdown ?? this.contentMarkdown),
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
    this.media,
    this.originalName,
  });

  final String lessonMediaId;
  final String lessonId;
  final int position;
  final String mediaType;
  final String state;
  final bool previewReady;
  final String? mediaAssetId;
  final ResolvedMediaData? media;
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
      media: _nullableResolvedMedia(payload, 'media', 'StudioLessonMediaItem'),
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
    ResolvedMediaData? media,
    String? originalName,
    bool clearMediaAssetId = false,
    bool clearMedia = false,
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
      media: clearMedia ? null : (media ?? this.media),
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
