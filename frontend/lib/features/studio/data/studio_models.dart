import 'package:flutter/foundation.dart';

import 'package:aveli/editor/document/lesson_document.dart';
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

String _requiredResponseText(Object? payload, String key, String label) {
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

String? _optionalResponseString(Object? payload, String key, String label) {
  switch (payload) {
    case final Map data when data.containsKey(key):
      final value = data[key];
      if (value == null) {
        return null;
      }
      if (value is String) {
        return value;
      }
      throw StateError('$label field "$key" must be a string or null');
    case final Map _:
      return null;
    default:
      throw StateError('$label returned a non-object payload');
  }
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

Map<String, Object?> _requiredResponseMap(
  Object? payload,
  String key,
  String label,
) {
  final value = _requireResponseField(payload, key, label);
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw StateError('$label field "$key" must be an object');
}

Map<String, Object?>? _nullableResponseMap(
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
        return Map<String, Object?>.from(value);
      }
      throw StateError('$label field "$key" must be an object or null');
    case final Map _:
      return null;
    default:
      throw StateError('$label returned a non-object payload');
  }
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

bool _responseHasField(Object? payload, String key) {
  return payload is Map && payload.containsKey(key);
}

enum DripAuthoringMode {
  noDripImmediateAccess('no_drip_immediate_access'),
  legacyUniformDrip('legacy_uniform_drip'),
  customLessonOffsets('custom_lesson_offsets');

  const DripAuthoringMode(this.apiValue);

  final String apiValue;

  static DripAuthoringMode fromApiValue(String value) {
    for (final mode in values) {
      if (mode.apiValue == value) {
        return mode;
      }
    }
    throw StateError('Unknown drip authoring mode: $value');
  }
}

enum DripAuthoringLockReason {
  firstEnrollmentExists('first_enrollment_exists');

  const DripAuthoringLockReason(this.apiValue);

  final String apiValue;

  static DripAuthoringLockReason fromApiValue(String value) {
    for (final reason in values) {
      if (reason.apiValue == value) {
        return reason;
      }
    }
    throw StateError('Unknown drip authoring lock reason: $value');
  }
}

@immutable
class LegacyUniform {
  const LegacyUniform({required this.dripIntervalDays});

  final int dripIntervalDays;

  factory LegacyUniform.fromResponse(
    Object? payload, {
    String label = 'LegacyUniform',
  }) {
    return LegacyUniform(
      dripIntervalDays: _requiredResponseInt(
        payload,
        'drip_interval_days',
        label,
      ),
    );
  }

  Map<String, Object?> toRequest() {
    return <String, Object?>{'drip_interval_days': dripIntervalDays};
  }
}

@immutable
class CustomScheduleRow {
  const CustomScheduleRow({
    required this.lessonId,
    required this.unlockOffsetDays,
  });

  final String lessonId;
  final int unlockOffsetDays;

  factory CustomScheduleRow.fromResponse(
    Object? payload, {
    String label = 'CustomScheduleRow',
  }) {
    return CustomScheduleRow(
      lessonId: _requiredResponseString(payload, 'lesson_id', label),
      unlockOffsetDays: _requiredResponseInt(
        payload,
        'unlock_offset_days',
        label,
      ),
    );
  }

  Map<String, Object?> toRequest() {
    return <String, Object?>{
      'lesson_id': lessonId,
      'unlock_offset_days': unlockOffsetDays,
    };
  }
}

@immutable
class CustomSchedule {
  const CustomSchedule({required this.rows});

  final List<CustomScheduleRow> rows;

  factory CustomSchedule.fromResponse(
    Object? payload, {
    String label = 'CustomSchedule',
  }) {
    final items = _requiredResponseList(payload, 'rows', label);
    return CustomSchedule(
      rows: items
          .map(
            (item) =>
                CustomScheduleRow.fromResponse(item, label: '$label.rows[]'),
          )
          .toList(growable: false),
    );
  }

  Map<String, Object?> toRequest() {
    return <String, Object?>{
      'rows': rows.map((row) => row.toRequest()).toList(growable: false),
    };
  }
}

@immutable
class DripAuthoring {
  const DripAuthoring({
    required this.mode,
    required this.scheduleLocked,
    required this.lockReason,
    required this.legacyUniform,
    required this.customSchedule,
  });

  const DripAuthoring.immediateAccess({
    this.scheduleLocked = false,
    this.lockReason,
  }) : mode = DripAuthoringMode.noDripImmediateAccess,
       legacyUniform = null,
       customSchedule = null;

  DripAuthoring.legacyUniform({
    required int dripIntervalDays,
    this.scheduleLocked = false,
    this.lockReason,
  }) : mode = DripAuthoringMode.legacyUniformDrip,
       legacyUniform = LegacyUniform(dripIntervalDays: dripIntervalDays),
       customSchedule = null;

  DripAuthoring.custom({
    required List<CustomScheduleRow> rows,
    this.scheduleLocked = false,
    this.lockReason,
  }) : mode = DripAuthoringMode.customLessonOffsets,
       legacyUniform = null,
       customSchedule = CustomSchedule(rows: rows);

  final DripAuthoringMode mode;
  final bool scheduleLocked;
  final DripAuthoringLockReason? lockReason;
  final LegacyUniform? legacyUniform;
  final CustomSchedule? customSchedule;

  bool get dripEnabled => mode == DripAuthoringMode.legacyUniformDrip;
  int? get dripIntervalDays => legacyUniform?.dripIntervalDays;
  List<CustomScheduleRow> get customScheduleRows =>
      customSchedule?.rows ?? const <CustomScheduleRow>[];

  factory DripAuthoring.fromResponse(
    Object? payload, {
    String label = 'DripAuthoring',
  }) {
    final mode = DripAuthoringMode.fromApiValue(
      _requiredResponseString(payload, 'mode', label),
    );
    final lockReasonRaw = _nullableResponseString(
      payload,
      'lock_reason',
      label,
    );
    final lockReason = lockReasonRaw == null
        ? null
        : DripAuthoringLockReason.fromApiValue(lockReasonRaw);
    final legacyUniformPayload = _nullableResponseMap(
      payload,
      'legacy_uniform',
      label,
    );
    final customSchedulePayload = _nullableResponseMap(
      payload,
      'custom_schedule',
      label,
    );
    return DripAuthoring(
      mode: mode,
      scheduleLocked: _requiredResponseBool(payload, 'schedule_locked', label),
      lockReason: lockReason,
      legacyUniform: legacyUniformPayload == null
          ? null
          : LegacyUniform.fromResponse(
              legacyUniformPayload,
              label: '$label.legacy_uniform',
            ),
      customSchedule: customSchedulePayload == null
          ? null
          : CustomSchedule.fromResponse(
              customSchedulePayload,
              label: '$label.custom_schedule',
            ),
    );
  }
}

DripAuthoring _legacyCourseDripAuthoring({
  required bool dripEnabled,
  required int? dripIntervalDays,
  bool scheduleLocked = false,
  DripAuthoringLockReason? lockReason,
}) {
  if (!dripEnabled) {
    return DripAuthoring.immediateAccess(
      scheduleLocked: scheduleLocked,
      lockReason: lockReason,
    );
  }
  if (dripIntervalDays == null || dripIntervalDays <= 0) {
    throw StateError('dripIntervalDays is required when dripEnabled is true');
  }
  return DripAuthoring.legacyUniform(
    dripIntervalDays: dripIntervalDays,
    scheduleLocked: scheduleLocked,
    lockReason: lockReason,
  );
}

DripAuthoring _courseDripAuthoringFromResponse(Object? payload, String label) {
  if (_responseHasField(payload, 'drip_authoring')) {
    return DripAuthoring.fromResponse(
      _requiredResponseMap(payload, 'drip_authoring', label),
      label: '$label.drip_authoring',
    );
  }
  return _legacyCourseDripAuthoring(
    dripEnabled: _requiredResponseBool(payload, 'drip_enabled', label),
    dripIntervalDays: _nullableResponseInt(
      payload,
      'drip_interval_days',
      label,
    ),
  );
}

DripAuthoring _copyCourseDripAuthoring(
  DripAuthoring current, {
  bool? dripEnabled,
  int? dripIntervalDays,
  bool clearDripIntervalDays = false,
}) {
  if (dripEnabled == null &&
      dripIntervalDays == null &&
      clearDripIntervalDays == false) {
    return current;
  }

  final nextDripEnabled =
      dripEnabled ??
      (clearDripIntervalDays
          ? false
          : (dripIntervalDays != null ? true : current.dripEnabled));
  if (!nextDripEnabled) {
    return DripAuthoring.immediateAccess(
      scheduleLocked: current.scheduleLocked,
      lockReason: current.lockReason,
    );
  }

  final nextIntervalDays = clearDripIntervalDays
      ? null
      : (dripIntervalDays ?? current.legacyUniform?.dripIntervalDays);
  if (nextIntervalDays == null || nextIntervalDays <= 0) {
    throw StateError('dripIntervalDays is required for legacy drip mode');
  }
  return DripAuthoring.legacyUniform(
    dripIntervalDays: nextIntervalDays,
    scheduleLocked: current.scheduleLocked,
    lockReason: current.lockReason,
  );
}

@immutable
class CourseCore {
  const CourseCore({
    required this.id,
    required this.title,
    required this.slug,
    this.shortDescription,
    required this.courseGroupId,
    required this.groupPosition,
    DripAuthoring? dripAuthoring,
    bool dripEnabled = false,
    int? dripIntervalDays,
    required this.coverMediaId,
    required this.cover,
  }) : assert(
         !dripEnabled || (dripIntervalDays != null && dripIntervalDays > 0),
         'dripIntervalDays is required when dripEnabled is true',
       ),
       _dripAuthoring = dripAuthoring,
       _dripEnabled = dripEnabled,
       _dripIntervalDays = dripIntervalDays;

  final String id;
  final String title;
  final String slug;
  final String? shortDescription;
  final String courseGroupId;
  final int groupPosition;
  final DripAuthoring? _dripAuthoring;
  final bool _dripEnabled;
  final int? _dripIntervalDays;
  final String? coverMediaId;
  final CourseCoverData? cover;

  DripAuthoring get dripAuthoring =>
      _dripAuthoring ??
      _legacyCourseDripAuthoring(
        dripEnabled: _dripEnabled,
        dripIntervalDays: _dripIntervalDays,
      );
  bool get dripEnabled => _dripAuthoring?.dripEnabled ?? _dripEnabled;
  int? get dripIntervalDays =>
      _dripAuthoring?.dripIntervalDays ?? _dripIntervalDays;
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
    super.shortDescription,
    required super.courseGroupId,
    required super.groupPosition,
    super.dripAuthoring,
    super.dripEnabled = false,
    super.dripIntervalDays,
    required super.coverMediaId,
    required super.cover,
    required this.priceAmountCents,
  });

  final int? priceAmountCents;

  factory CourseStudio.fromResponse(
    Object? payload, {
    String label = 'Course',
  }) {
    final dripAuthoring = _courseDripAuthoringFromResponse(payload, label);
    return CourseStudio(
      id: _requiredResponseString(payload, 'id', label),
      title: _requiredResponseString(payload, 'title', label),
      slug: _requiredResponseString(payload, 'slug', label),
      shortDescription: _optionalResponseString(
        payload,
        'short_description',
        label,
      ),
      courseGroupId: _requiredResponseString(payload, 'course_group_id', label),
      groupPosition: _requiredResponseInt(payload, 'group_position', label),
      dripAuthoring: dripAuthoring,
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
    String? shortDescription,
    String? courseGroupId,
    int? groupPosition,
    DripAuthoring? dripAuthoring,
    bool? dripEnabled,
    int? dripIntervalDays,
    String? coverMediaId,
    CourseCoverData? cover,
    int? priceAmountCents,
    bool clearCourseGroupId = false,
    bool clearShortDescription = false,
    bool clearDripIntervalDays = false,
    bool clearCoverMediaId = false,
    bool clearCover = false,
    bool clearPriceAmountCents = false,
  }) {
    final nextDripAuthoring =
        dripAuthoring ??
        _copyCourseDripAuthoring(
          this.dripAuthoring,
          dripEnabled: dripEnabled,
          dripIntervalDays: dripIntervalDays,
          clearDripIntervalDays: clearDripIntervalDays,
        );
    return CourseStudio(
      id: id ?? this.id,
      title: title ?? this.title,
      slug: slug ?? this.slug,
      shortDescription: clearShortDescription
          ? null
          : (shortDescription ?? this.shortDescription),
      courseGroupId: clearCourseGroupId
          ? ''
          : (courseGroupId ?? this.courseGroupId),
      groupPosition: groupPosition ?? this.groupPosition,
      dripAuthoring: nextDripAuthoring,
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
class StudioCoursePublicContent {
  const StudioCoursePublicContent({
    required this.courseId,
    required this.description,
  });

  final String courseId;
  final String description;

  factory StudioCoursePublicContent.fromResponse(
    Object? payload, {
    String label = 'StudioCoursePublicContent',
  }) {
    return StudioCoursePublicContent(
      courseId: _requiredResponseString(payload, 'course_id', label),
      description: _requiredResponseText(payload, 'description', label),
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
      'content_document',
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
    required this.contentDocument,
    required List<StudioLessonContentMediaItem> media,
    required String etag,
  }) : media = List<StudioLessonContentMediaItem>.unmodifiable(media),
       etag = _requireTransportEtag(etag, 'StudioLessonContentRead');

  final String lessonId;
  final LessonDocument contentDocument;
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
      contentDocument: LessonDocument.fromJson(
        _requireResponseField(
          payload,
          'content_document',
          'StudioLessonContentRead',
        ),
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
    required this.contentDocument,
    required this.etag,
  });

  final String lessonId;
  final LessonDocument contentDocument;
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
      contentDocument: LessonDocument.fromJson(
        _requireResponseField(
          payload,
          'content_document',
          'StudioLessonContentWriteResult',
        ),
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
