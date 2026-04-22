import 'package:flutter/foundation.dart';

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

List<Object?> _requiredResponseList(Object? payload, String key, String label) {
  final value = _requireResponseField(payload, key, label);
  if (value is List) {
    return List<Object?>.from(value);
  }
  throw StateError('$label field "$key" must be a list');
}

List<String> _requiredResponseStringList(
  Object? payload,
  String key,
  String label,
) {
  final items = _requiredResponseList(payload, key, label);
  return items
      .map((item) {
        if (item is String && item.trim().isNotEmpty) {
          return item.trim();
        }
        throw StateError('$label field "$key" must contain non-empty strings');
      })
      .toList(growable: false);
}

void _rejectResponseFields(
  Object? payload,
  Iterable<String> keys,
  String label,
) {
  switch (payload) {
    case final Map data:
      for (final key in keys) {
        if (data.containsKey(key)) {
          throw StateError('$label must not include field "$key"');
        }
      }
    default:
      throw StateError('$label returned a non-object payload');
  }
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
    required this.groupPosition,
    required this.dripEnabled,
    required this.dripIntervalDays,
    required this.coverMediaId,
    required this.cover,
  });

  final String id;
  final String title;
  final String slug;
  final String courseGroupId;
  final int groupPosition;
  final bool dripEnabled;
  final int? dripIntervalDays;
  final String? coverMediaId;
  final CourseCoverData? cover;
}

@immutable
class CourseFamilyStudio {
  const CourseFamilyStudio({
    required this.id,
    required this.name,
    required this.teacherId,
    required this.createdAt,
    required this.courseCount,
  });

  final String id;
  final String name;
  final String teacherId;
  final DateTime createdAt;
  final int courseCount;

  factory CourseFamilyStudio.fromResponse(
    Object? payload, {
    String label = 'CourseFamily',
  }) {
    return CourseFamilyStudio(
      id: _requiredResponseString(payload, 'id', label),
      name: _requiredResponseString(payload, 'name', label),
      teacherId: _requiredResponseString(payload, 'teacher_id', label),
      createdAt: _requiredResponseUtcDateTime(payload, 'created_at', label),
      courseCount: _requiredResponseInt(payload, 'course_count', label),
    );
  }
}

@immutable
class CourseStudio extends CourseCore {
  const CourseStudio({
    required super.id,
    required super.title,
    required super.slug,
    required super.courseGroupId,
    required super.groupPosition,
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
      groupPosition: _requiredResponseInt(payload, 'group_position', label),
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
    int? groupPosition,
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
      groupPosition: groupPosition ?? this.groupPosition,
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
  });

  final String id;
  final String courseId;
  final String lessonTitle;
  final int position;

  factory LessonStudio.fromResponse(
    Object? payload, {
    String label = 'StudioLesson',
  }) {
    _rejectResponseFields(payload, const [
      'content_markdown',
      'media',
      'etag',
    ], label);
    return LessonStudio(
      id: _requiredResponseString(payload, 'id', label),
      courseId: _requiredResponseString(payload, 'course_id', label),
      lessonTitle: _requiredResponseString(payload, 'lesson_title', label),
      position: _requiredResponseInt(payload, 'position', label),
    );
  }

  LessonStudio copyWith({
    String? id,
    String? courseId,
    String? lessonTitle,
    int? position,
  }) {
    return LessonStudio(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      lessonTitle: lessonTitle ?? this.lessonTitle,
      position: position ?? this.position,
    );
  }
}

@immutable
class StudioLessonContentMediaItem {
  const StudioLessonContentMediaItem({
    required this.lessonMediaId,
    required this.position,
    required this.mediaType,
    required this.state,
    this.mediaAssetId,
  });

  final String lessonMediaId;
  final int position;
  final String mediaType;
  final String state;
  final String? mediaAssetId;

  factory StudioLessonContentMediaItem.fromResponse(Object? payload) {
    return StudioLessonContentMediaItem(
      lessonMediaId: _requiredResponseString(
        payload,
        'lesson_media_id',
        'StudioLessonContentMediaItem',
      ),
      position: _requiredResponseInt(
        payload,
        'position',
        'StudioLessonContentMediaItem',
      ),
      mediaType: _requiredResponseString(
        payload,
        'media_type',
        'StudioLessonContentMediaItem',
      ),
      state: _requiredResponseString(
        payload,
        'state',
        'StudioLessonContentMediaItem',
      ),
      mediaAssetId: _nullableResponseString(
        payload,
        'media_asset_id',
        'StudioLessonContentMediaItem',
      ),
    );
  }
}

@immutable
class StudioLessonContentRead {
  StudioLessonContentRead({
    required this.lessonId,
    required this.contentMarkdown,
    required List<StudioLessonContentMediaItem> media,
    required String etag,
  }) : media = List<StudioLessonContentMediaItem>.unmodifiable(media),
       etag = _requireTransportEtag(etag, 'StudioLessonContentRead');

  final String lessonId;
  final String contentMarkdown;
  final List<StudioLessonContentMediaItem> media;
  final String etag;

  factory StudioLessonContentRead.fromResponse(
    Object? payload, {
    required String etag,
  }) {
    return StudioLessonContentRead(
      lessonId: _requiredResponseString(
        payload,
        'lesson_id',
        'StudioLessonContentRead',
      ),
      contentMarkdown: _requiredResponseStringValue(
        payload,
        'content_markdown',
        'StudioLessonContentRead',
      ),
      media: _requiredResponseList(
        payload,
        'media',
        'StudioLessonContentRead',
      ).map(StudioLessonContentMediaItem.fromResponse).toList(growable: false),
      etag: etag,
    );
  }
}

@immutable
class StudioLessonContentWriteResult {
  const StudioLessonContentWriteResult({
    required this.lessonId,
    required this.contentMarkdown,
    required this.etag,
  });

  final String lessonId;
  final String contentMarkdown;
  final String etag;

  factory StudioLessonContentWriteResult.fromResponse(
    Object? payload, {
    required String etag,
  }) {
    return StudioLessonContentWriteResult(
      lessonId: _requiredResponseString(
        payload,
        'lesson_id',
        'StudioLessonContentWriteResult',
      ),
      contentMarkdown: _requiredResponseStringValue(
        payload,
        'content_markdown',
        'StudioLessonContentWriteResult',
      ),
      etag: _requireTransportEtag(etag, 'StudioLessonContentWriteResult'),
    );
  }
}

String _requireTransportEtag(String value, String label) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw StateError('$label requires a non-empty ETag transport token');
  }
  return normalized;
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
    final media = _nullableResolvedMedia(
      payload,
      'media',
      'StudioLessonMediaItem',
    );
    final resolvedUrl = media?.resolvedUrl?.trim();
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
      previewReady: resolvedUrl != null && resolvedUrl.isNotEmpty,
      mediaAssetId: _nullableResponseString(
        payload,
        'media_asset_id',
        'StudioLessonMediaItem',
      ),
      media: media,
    );
  }

  factory StudioLessonMediaItem.fromPlacementResponse(Object? payload) {
    final media = _nullableResolvedMedia(
      payload,
      'media',
      'StudioLessonMediaPlacement',
    );
    final resolvedUrl = media?.resolvedUrl?.trim();
    return StudioLessonMediaItem(
      lessonMediaId: _requiredResponseString(
        payload,
        'lesson_media_id',
        'StudioLessonMediaPlacement',
      ),
      lessonId: _requiredResponseString(
        payload,
        'lesson_id',
        'StudioLessonMediaPlacement',
      ),
      position: _requiredResponseInt(
        payload,
        'position',
        'StudioLessonMediaPlacement',
      ),
      mediaType: _requiredResponseString(
        payload,
        'media_type',
        'StudioLessonMediaPlacement',
      ),
      state: _requiredResponseString(
        payload,
        'asset_state',
        'StudioLessonMediaPlacement',
      ),
      previewReady: resolvedUrl != null && resolvedUrl.isNotEmpty,
      mediaAssetId: _nullableResponseString(
        payload,
        'media_asset_id',
        'StudioLessonMediaPlacement',
      ),
      media: media,
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
    required this.mediaAssetId,
    required this.assetState,
    required this.uploadSessionId,
    required this.uploadEndpoint,
    required this.expiresAt,
  });

  final String mediaAssetId;
  final String assetState;
  final String uploadSessionId;
  final String uploadEndpoint;
  final DateTime expiresAt;

  factory StudioLessonMediaUploadTarget.fromResponse(Object? payload) {
    return StudioLessonMediaUploadTarget(
      mediaAssetId: _requiredResponseString(
        payload,
        'media_asset_id',
        'StudioLessonMediaUploadTarget',
      ),
      assetState: _requiredResponseString(
        payload,
        'asset_state',
        'StudioLessonMediaUploadTarget',
      ),
      uploadSessionId: _requiredResponseString(
        payload,
        'upload_session_id',
        'StudioLessonMediaUploadTarget',
      ),
      uploadEndpoint: _requiredResponseString(
        payload,
        'upload_endpoint',
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
    return StudioLessonMediaPreviewItem.fromPlacementResponse(
      lessonMediaId,
      payload,
    );
  }

  factory StudioLessonMediaPreviewItem.fromPlacementResponse(
    String lessonMediaId,
    Object? payload,
  ) {
    final media = _nullableResolvedMedia(
      payload,
      'media',
      'StudioLessonMediaPreviewItem',
    );
    final resolvedUrl = media?.resolvedUrl?.trim();
    final assetState = _requiredResponseString(
      payload,
      'asset_state',
      'StudioLessonMediaPreviewItem',
    );
    final isReady =
        assetState == 'ready' && resolvedUrl != null && resolvedUrl.isNotEmpty;
    return StudioLessonMediaPreviewItem(
      lessonMediaId: lessonMediaId,
      mediaType: _requiredResponseString(
        payload,
        'media_type',
        'StudioLessonMediaPreviewItem',
      ),
      authoritativeEditorReady: isReady,
      previewUrl: isReady ? resolvedUrl : null,
      failureReason: assetState == 'failed' ? 'failed' : null,
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

@immutable
class SpecialOfferExecutionState {
  SpecialOfferExecutionState({
    required this.specialOfferId,
    required this.activeOutputId,
    required this.activeMediaAssetId,
    required this.stateHash,
    required this.attemptId,
    required this.status,
    required this.textId,
    required this.sourceCount,
    required this.overwriteApplied,
    required this.imageCurrent,
    required this.imageRequired,
    required this.priceAmountCents,
    required List<String> courseIds,
    required this.image,
  }) : courseIds = List<String>.unmodifiable(courseIds);

  final String specialOfferId;
  final String? activeOutputId;
  final String? activeMediaAssetId;
  final String stateHash;
  final String? attemptId;
  final String? status;
  final String? textId;
  final int sourceCount;
  final bool overwriteApplied;
  final bool imageCurrent;
  final bool imageRequired;
  final int priceAmountCents;
  final List<String> courseIds;
  final ResolvedMediaData? image;

  bool get hasRenderableImage {
    final resolvedUrl = image?.resolvedUrl?.trim();
    return image?.state == 'ready' &&
        resolvedUrl != null &&
        resolvedUrl.isNotEmpty;
  }

  factory SpecialOfferExecutionState.fromResponse(
    Object? payload, {
    String label = 'SpecialOfferExecutionState',
  }) {
    final imageValue = _requireResponseField(payload, 'image', label);
    return SpecialOfferExecutionState(
      specialOfferId: _requiredResponseString(
        payload,
        'special_offer_id',
        label,
      ),
      activeOutputId: _nullableResponseString(
        payload,
        'active_output_id',
        label,
      ),
      activeMediaAssetId: _nullableResponseString(
        payload,
        'active_media_asset_id',
        label,
      ),
      stateHash: _requiredResponseString(payload, 'state_hash', label),
      attemptId: _nullableResponseString(payload, 'attempt_id', label),
      status: _nullableResponseString(payload, 'status', label),
      textId: _nullableResponseString(payload, 'text_id', label),
      sourceCount: _requiredResponseInt(payload, 'source_count', label),
      overwriteApplied: _requiredResponseBool(
        payload,
        'overwrite_applied',
        label,
      ),
      imageCurrent: _requiredResponseBool(payload, 'image_current', label),
      imageRequired: _requiredResponseBool(payload, 'image_required', label),
      priceAmountCents: _requiredResponseInt(
        payload,
        'price_amount_cents',
        label,
      ),
      courseIds: _requiredResponseStringList(payload, 'course_ids', label),
      image: switch (imageValue) {
        null => null,
        final Map<String, dynamic> data => ResolvedMediaData.fromJson(data),
        final Map data => ResolvedMediaData.fromJson(
          Map<String, dynamic>.from(data),
        ),
        final Object _ => throw StateError(
          '$label field "image" must be an object or null',
        ),
      },
    );
  }
}
