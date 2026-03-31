import 'package:equatable/equatable.dart';

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

int _requireInt(Object? value, String fieldName) {
  switch (value) {
    case final int number:
      return number;
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

bool _requireBool(Object? value, String fieldName) {
  switch (value) {
    case final bool flag:
      return flag;
    default:
      throw FormatException('Invalid field type for $fieldName');
  }
}

DateTime _requireDateTime(Object? value, String fieldName) {
  return DateTime.parse(_requireString(value, fieldName));
}

DateTime? _optionalDateTime(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    default:
      return _requireDateTime(value, fieldName);
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

enum TeacherProfileMediaKind {
  lessonMedia('lesson_media'),
  seminarRecording('seminar_recording'),
  external('external');

  const TeacherProfileMediaKind(this.apiValue);

  final String apiValue;

  static TeacherProfileMediaKind fromApi(String value) {
    return TeacherProfileMediaKind.values.firstWhere(
      (kind) => kind.apiValue == value,
      orElse: () => throw ArgumentError.value(
        value,
        'value',
        'Unknown teacher profile media kind',
      ),
    );
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
    this.downloadUrl,
    this.signedUrl,
    this.signedUrlExpiresAt,
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
      downloadUrl: _optionalString(
        _requiredField(payload, 'download_url'),
        'download_url',
      ),
      signedUrl: _optionalString(
        _requiredField(payload, 'signed_url'),
        'signed_url',
      ),
      signedUrlExpiresAt: _optionalString(
        _requiredField(payload, 'signed_url_expires_at'),
        'signed_url_expires_at',
      ),
    );
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
  final String? downloadUrl;
  final String? signedUrl;
  final String? signedUrlExpiresAt;

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
    downloadUrl,
    signedUrl,
    signedUrlExpiresAt,
  ];
}

class TeacherProfileRecordingSource extends Equatable {
  const TeacherProfileRecordingSource({
    required this.id,
    required this.seminarId,
    this.seminarTitle,
    this.sessionId,
    required this.assetUrl,
    required this.status,
    this.durationSeconds,
    this.byteSize,
    required this.published,
    this.createdAt,
    this.updatedAt,
  });

  factory TeacherProfileRecordingSource.fromResponse(Object? payload) {
    return TeacherProfileRecordingSource(
      id: _requireString(_requiredField(payload, 'id'), 'id'),
      seminarId: _requireString(
        _requiredField(payload, 'seminar_id'),
        'seminar_id',
      ),
      seminarTitle: _optionalString(
        _requiredField(payload, 'seminar_title'),
        'seminar_title',
      ),
      sessionId: _optionalString(
        _requiredField(payload, 'session_id'),
        'session_id',
      ),
      assetUrl: _requireString(
        _requiredField(payload, 'asset_url'),
        'asset_url',
      ),
      status: _requireString(_requiredField(payload, 'status'), 'status'),
      durationSeconds: _optionalInt(
        _requiredField(payload, 'duration_seconds'),
        'duration_seconds',
      ),
      byteSize: _optionalInt(_requiredField(payload, 'byte_size'), 'byte_size'),
      published: _requireBool(
        _requiredField(payload, 'published'),
        'published',
      ),
      createdAt: _optionalDateTime(
        _requiredField(payload, 'created_at'),
        'created_at',
      ),
      updatedAt: _optionalDateTime(
        _requiredField(payload, 'updated_at'),
        'updated_at',
      ),
    );
  }

  final String id;
  final String seminarId;
  final String? seminarTitle;
  final String? sessionId;
  final String assetUrl;
  final String status;
  final int? durationSeconds;
  final int? byteSize;
  final bool published;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  @override
  List<Object?> get props => [
    id,
    seminarId,
    seminarTitle,
    sessionId,
    assetUrl,
    status,
    durationSeconds,
    byteSize,
    published,
    createdAt,
    updatedAt,
  ];
}

class TeacherProfileMediaItem extends Equatable {
  const TeacherProfileMediaItem({
    required this.id,
    required this.teacherId,
    required this.mediaKind,
    this.lessonMediaId,
    this.seminarRecordingId,
    this.externalUrl,
    this.title,
    this.description,
    this.coverMediaId,
    this.coverImageUrl,
    required this.position,
    required this.isPublished,
    required this.enabledForHomePlayer,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TeacherProfileMediaItem.fromResponse(Object? payload) {
    return TeacherProfileMediaItem(
      id: _requireString(_requiredField(payload, 'id'), 'id'),
      teacherId: _requireString(
        _requiredField(payload, 'teacher_id'),
        'teacher_id',
      ),
      mediaKind: TeacherProfileMediaKind.fromApi(
        _requireString(_requiredField(payload, 'media_kind'), 'media_kind'),
      ),
      lessonMediaId: _optionalString(
        _requiredField(payload, 'lesson_media_id'),
        'lesson_media_id',
      ),
      seminarRecordingId: _optionalString(
        _requiredField(payload, 'seminar_recording_id'),
        'seminar_recording_id',
      ),
      externalUrl: _optionalString(
        _requiredField(payload, 'external_url'),
        'external_url',
      ),
      title: _optionalString(_requiredField(payload, 'title'), 'title'),
      description: _optionalString(
        _requiredField(payload, 'description'),
        'description',
      ),
      coverMediaId: _optionalString(
        _requiredField(payload, 'cover_media_id'),
        'cover_media_id',
      ),
      coverImageUrl: _optionalString(
        _requiredField(payload, 'cover_image_url'),
        'cover_image_url',
      ),
      position: _requireInt(_requiredField(payload, 'position'), 'position'),
      isPublished: _requireBool(
        _requiredField(payload, 'is_published'),
        'is_published',
      ),
      enabledForHomePlayer: _requireBool(
        _requiredField(payload, 'enabled_for_home_player'),
        'enabled_for_home_player',
      ),
      createdAt: _requireDateTime(
        _requiredField(payload, 'created_at'),
        'created_at',
      ),
      updatedAt: _requireDateTime(
        _requiredField(payload, 'updated_at'),
        'updated_at',
      ),
    );
  }

  final String id;
  final String teacherId;
  final TeacherProfileMediaKind mediaKind;
  final String? lessonMediaId;
  final String? seminarRecordingId;
  final String? externalUrl;
  final String? title;
  final String? description;
  final String? coverMediaId;
  final String? coverImageUrl;
  final int position;
  final bool isPublished;
  final bool enabledForHomePlayer;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool matchesSourceReference(
    TeacherProfileMediaKind kind,
    String sourceReference,
  ) {
    switch (kind) {
      case TeacherProfileMediaKind.lessonMedia:
        return mediaKind == kind && lessonMediaId == sourceReference;
      case TeacherProfileMediaKind.seminarRecording:
        return mediaKind == kind && seminarRecordingId == sourceReference;
      case TeacherProfileMediaKind.external:
        return mediaKind == kind && externalUrl == sourceReference;
    }
  }

  @override
  List<Object?> get props => [
    id,
    teacherId,
    mediaKind,
    lessonMediaId,
    seminarRecordingId,
    externalUrl,
    title,
    description,
    coverMediaId,
    coverImageUrl,
    position,
    isPublished,
    enabledForHomePlayer,
    createdAt,
    updatedAt,
  ];
}

class TeacherProfileMediaPayload extends Equatable {
  const TeacherProfileMediaPayload({
    required this.items,
    required this.lessonMediaSources,
    required this.seminarRecordingSources,
  });

  factory TeacherProfileMediaPayload.fromResponse(Object? payload) {
    final itemsJson = _requireList(_requiredField(payload, 'items'), 'items');
    final lessonsJson = _requireList(
      _requiredField(payload, 'lesson_media_sources'),
      'lesson_media_sources',
    );
    final recordingsJson = _requireList(
      _requiredField(payload, 'seminar_recording_sources'),
      'seminar_recording_sources',
    );

    return TeacherProfileMediaPayload(
      items: itemsJson
          .map(TeacherProfileMediaItem.fromResponse)
          .toList(growable: false),
      lessonMediaSources: lessonsJson
          .map(TeacherProfileLessonSource.fromResponse)
          .toList(growable: false),
      seminarRecordingSources: recordingsJson
          .map(TeacherProfileRecordingSource.fromResponse)
          .toList(growable: false),
    );
  }

  static const empty = TeacherProfileMediaPayload(
    items: [],
    lessonMediaSources: [],
    seminarRecordingSources: [],
  );

  final List<TeacherProfileMediaItem> items;
  final List<TeacherProfileLessonSource> lessonMediaSources;
  final List<TeacherProfileRecordingSource> seminarRecordingSources;

  TeacherProfileLessonSource? lessonSourceFor(TeacherProfileMediaItem item) {
    final lessonMediaId = item.lessonMediaId;
    if (lessonMediaId == null) {
      return null;
    }
    for (final source in lessonMediaSources) {
      if (source.id == lessonMediaId) {
        return source;
      }
    }
    return null;
  }

  TeacherProfileRecordingSource? recordingSourceFor(
    TeacherProfileMediaItem item,
  ) {
    final seminarRecordingId = item.seminarRecordingId;
    if (seminarRecordingId == null) {
      return null;
    }
    for (final source in seminarRecordingSources) {
      if (source.id == seminarRecordingId) {
        return source;
      }
    }
    return null;
  }

  @override
  List<Object?> get props => [
    items,
    lessonMediaSources,
    seminarRecordingSources,
  ];
}
