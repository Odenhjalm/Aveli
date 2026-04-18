import 'package:equatable/equatable.dart';
import 'package:aveli/shared/utils/resolved_media_contract.dart';

Object? _requiredField(Object? payload, String fieldName) {
  switch (payload) {
    case final Map<Object?, Object?> data when data.containsKey(fieldName):
      return data[fieldName];
    case final Map<Object?, Object?> _:
      throw FormatException('Missing required field: $fieldName');
    default:
      throw FormatException('Invalid payload for $fieldName');
  }
}

String _requireString(Object? value, String fieldName) {
  switch (value) {
    case final String text when text.trim().isNotEmpty:
      return text.trim();
    default:
      throw FormatException('Invalid field type for $fieldName');
  }
}

String? _optionalString(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    case final String text:
      final normalized = text.trim();
      return normalized.isEmpty ? null : normalized;
    default:
      throw FormatException('Invalid field type for $fieldName');
  }
}

int? _optionalInt(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    case final int number:
      return number;
    default:
      throw FormatException('Invalid field type for $fieldName');
  }
}

DateTime? _optionalDateTime(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    case final String text:
      return DateTime.parse(text);
    default:
      throw FormatException('Invalid field type for $fieldName');
  }
}

List<Object?> _requireList(Object? value, String fieldName) {
  switch (value) {
    case final List items:
      return List<Object?>.unmodifiable(items);
    default:
      throw FormatException('Invalid field type for $fieldName');
  }
}

ResolvedMediaData? _optionalResolvedMedia(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    case final Map<String, dynamic> data:
      return ResolvedMediaData.fromJson(data);
    case final Map data:
      return ResolvedMediaData.fromJson(Map<String, dynamic>.from(data));
    default:
      throw FormatException('Invalid field type for $fieldName');
  }
}

class TeacherProfileLessonSource extends Equatable {
  const TeacherProfileLessonSource({
    required this.id,
    required this.lessonId,
    this.lessonTitle,
    this.courseId,
    this.courseTitle,
    this.courseSlug,
    required this.kind,
    this.storagePath,
    this.storageBucket,
    this.contentType,
    this.durationSeconds,
    this.position,
    this.createdAt,
    this.media,
  });

  factory TeacherProfileLessonSource.fromResponse(Object? payload) {
    return TeacherProfileLessonSource(
      id: _requireString(_requiredField(payload, 'id'), 'id'),
      lessonId: _requireString(
        _requiredField(payload, 'lesson_id'),
        'lesson_id',
      ),
      lessonTitle: _optionalString(
        _requiredField(payload, 'lesson_title'),
        'lesson_title',
      ),
      courseId: _optionalString(
        _requiredField(payload, 'course_id'),
        'course_id',
      ),
      courseTitle: _optionalString(
        _requiredField(payload, 'course_title'),
        'course_title',
      ),
      courseSlug: _optionalString(
        _requiredField(payload, 'course_slug'),
        'course_slug',
      ),
      kind: _requireString(_requiredField(payload, 'kind'), 'kind'),
      storagePath: _optionalString(
        _requiredField(payload, 'storage_path'),
        'storage_path',
      ),
      storageBucket: _optionalString(
        _requiredField(payload, 'storage_bucket'),
        'storage_bucket',
      ),
      contentType: _optionalString(
        _requiredField(payload, 'content_type'),
        'content_type',
      ),
      durationSeconds: _optionalInt(
        _requiredField(payload, 'duration_seconds'),
        'duration_seconds',
      ),
      position: _optionalInt(_requiredField(payload, 'position'), 'position'),
      createdAt: _optionalDateTime(
        _requiredField(payload, 'created_at'),
        'created_at',
      ),
      media: _optionalResolvedMedia(_requiredField(payload, 'media'), 'media'),
    );
  }

  factory TeacherProfileLessonSource.fromJson(Object? payload) {
    return TeacherProfileLessonSource.fromResponse(payload);
  }

  final String id;
  final String lessonId;
  final String? lessonTitle;
  final String? courseId;
  final String? courseTitle;
  final String? courseSlug;
  final String kind;
  final String? storagePath;
  final String? storageBucket;
  final String? contentType;
  final int? durationSeconds;
  final int? position;
  final DateTime? createdAt;
  final ResolvedMediaData? media;

  @override
  List<Object?> get props => [
    id,
    lessonId,
    lessonTitle,
    courseId,
    courseTitle,
    courseSlug,
    kind,
    storagePath,
    storageBucket,
    contentType,
    durationSeconds,
    position,
    createdAt,
    media,
  ];
}

class TeacherProfileMediaItem extends Equatable {
  const TeacherProfileMediaItem({
    required this.id,
    required this.subjectUserId,
    required this.mediaAssetId,
    required this.visibility,
    this.media,
  });

  factory TeacherProfileMediaItem.fromResponse(Object? payload) {
    return TeacherProfileMediaItem(
      id: _requireString(_requiredField(payload, 'id'), 'id'),
      subjectUserId: _requireString(
        _requiredField(payload, 'subject_user_id'),
        'subject_user_id',
      ),
      mediaAssetId: _requireString(
        _requiredField(payload, 'media_asset_id'),
        'media_asset_id',
      ),
      visibility: _requireString(
        _requiredField(payload, 'visibility'),
        'visibility',
      ),
      media: _optionalResolvedMedia(_requiredField(payload, 'media'), 'media'),
    );
  }

  factory TeacherProfileMediaItem.fromJson(Object? payload) {
    return TeacherProfileMediaItem.fromResponse(payload);
  }

  final String id;
  final String subjectUserId;
  final String mediaAssetId;
  final String visibility;
  final ResolvedMediaData? media;

  bool get isPublished => visibility == 'published';

  @override
  List<Object?> get props => [
    id,
    subjectUserId,
    mediaAssetId,
    visibility,
    media,
  ];
}

class TeacherProfileMediaPayload extends Equatable {
  const TeacherProfileMediaPayload({required this.items});

  factory TeacherProfileMediaPayload.fromResponse(Object? payload) {
    final itemsJson = _requireList(_requiredField(payload, 'items'), 'items');
    return TeacherProfileMediaPayload(
      items: itemsJson
          .map(TeacherProfileMediaItem.fromResponse)
          .toList(growable: false),
    );
  }

  factory TeacherProfileMediaPayload.fromJson(Object? payload) {
    return TeacherProfileMediaPayload.fromResponse(payload);
  }

  static const empty = TeacherProfileMediaPayload(items: []);

  final List<TeacherProfileMediaItem> items;

  @override
  List<Object?> get props => [items];
}
