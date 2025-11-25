import 'package:equatable/equatable.dart';

enum TeacherProfileMediaKind {
  lessonMedia('lesson_media'),
  seminarRecording('seminar_recording'),
  external('external');

  const TeacherProfileMediaKind(this.apiValue);

  final String apiValue;

  static TeacherProfileMediaKind fromApi(String value) {
    return TeacherProfileMediaKind.values.firstWhere(
      (kind) => kind.apiValue == value,
      orElse: () => TeacherProfileMediaKind.external,
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

  factory TeacherProfileLessonSource.fromJson(Map<String, dynamic> json) {
    return TeacherProfileLessonSource(
      id: json['id'] as String,
      lessonId: json['lesson_id'] as String,
      lessonTitle: json['lesson_title'] as String?,
      courseId: json['course_id'] as String?,
      courseTitle: json['course_title'] as String?,
      courseSlug: json['course_slug'] as String?,
      kind: json['kind'] as String? ?? 'audio',
      storagePath: json['storage_path'] as String?,
      storageBucket: json['storage_bucket'] as String? ?? 'lesson-media',
      contentType: json['content_type'] as String?,
      durationSeconds: json['duration_seconds'] as int?,
      position: json['position'] as int?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      downloadUrl: json['download_url'] as String?,
      signedUrl: json['signed_url'] as String?,
      signedUrlExpiresAt: json['signed_url_expires_at'] as String?,
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

  TeacherProfileLessonSource copyWith({
    String? downloadUrl,
    String? signedUrl,
    String? signedUrlExpiresAt,
  }) {
    return TeacherProfileLessonSource(
      id: id,
      lessonId: lessonId,
      lessonTitle: lessonTitle,
      courseId: courseId,
      courseTitle: courseTitle,
      courseSlug: courseSlug,
      kind: kind,
      storagePath: storagePath,
      storageBucket: storageBucket,
      contentType: contentType,
      durationSeconds: durationSeconds,
      position: position,
      createdAt: createdAt,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      signedUrl: signedUrl ?? this.signedUrl,
      signedUrlExpiresAt: signedUrlExpiresAt ?? this.signedUrlExpiresAt,
    );
  }

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
    this.metadata = const {},
    this.createdAt,
    this.updatedAt,
  });

  factory TeacherProfileRecordingSource.fromJson(Map<String, dynamic> json) {
    return TeacherProfileRecordingSource(
      id: json['id'] as String,
      seminarId: json['seminar_id'] as String,
      seminarTitle: json['seminar_title'] as String?,
      sessionId: json['session_id'] as String?,
      assetUrl: json['asset_url'] as String,
      status: json['status'] as String? ?? 'processing',
      durationSeconds: json['duration_seconds'] as int?,
      byteSize: json['byte_size'] as int?,
      published: json['published'] as bool? ?? false,
      metadata: Map<String, dynamic>.from(
        (json['metadata'] as Map?) ?? const {},
      ),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
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
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TeacherProfileRecordingSource copyWith({String? assetUrl}) {
    return TeacherProfileRecordingSource(
      id: id,
      seminarId: seminarId,
      seminarTitle: seminarTitle,
      sessionId: sessionId,
      assetUrl: assetUrl ?? this.assetUrl,
      status: status,
      durationSeconds: durationSeconds,
      byteSize: byteSize,
      published: published,
      metadata: metadata,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

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
    metadata,
    createdAt,
    updatedAt,
  ];
}

class TeacherProfileMediaSource extends Equatable {
  const TeacherProfileMediaSource({this.lessonMedia, this.seminarRecording});

  factory TeacherProfileMediaSource.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TeacherProfileMediaSource();
    final lessonJson = json['lesson_media'];
    final seminarJson = json['seminar_recording'];
    return TeacherProfileMediaSource(
      lessonMedia: lessonJson is Map
          ? TeacherProfileLessonSource.fromJson(
              Map<String, dynamic>.from(lessonJson),
            )
          : null,
      seminarRecording: seminarJson is Map
          ? TeacherProfileRecordingSource.fromJson(
              Map<String, dynamic>.from(seminarJson),
            )
          : null,
    );
  }

  final TeacherProfileLessonSource? lessonMedia;
  final TeacherProfileRecordingSource? seminarRecording;

  TeacherProfileMediaSource copyWith({
    TeacherProfileLessonSource? lessonMedia,
    TeacherProfileRecordingSource? seminarRecording,
  }) {
    return TeacherProfileMediaSource(
      lessonMedia: lessonMedia ?? this.lessonMedia,
      seminarRecording: seminarRecording ?? this.seminarRecording,
    );
  }

  @override
  List<Object?> get props => [lessonMedia, seminarRecording];
}

class TeacherProfileMediaItem extends Equatable {
  const TeacherProfileMediaItem({
    required this.id,
    required this.teacherId,
    required this.mediaKind,
    this.mediaId,
    this.externalUrl,
    this.title,
    this.description,
    this.coverMediaId,
    this.coverImageUrl,
    required this.position,
    required this.isPublished,
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
    this.source = const TeacherProfileMediaSource(),
  });

  factory TeacherProfileMediaItem.fromJson(Map<String, dynamic> json) {
    final kind = TeacherProfileMediaKind.fromApi(
      json['media_kind'] as String? ?? 'external',
    );
    return TeacherProfileMediaItem(
      id: json['id'] as String,
      teacherId: json['teacher_id'] as String,
      mediaKind: kind,
      mediaId: json['media_id'] as String?,
      externalUrl: json['external_url'] as String?,
      title: json['title'] as String?,
      description: json['description'] as String?,
      coverMediaId: json['cover_media_id'] as String?,
      coverImageUrl: json['cover_image_url'] as String?,
      position: json['position'] as int? ?? 0,
      isPublished: json['is_published'] as bool? ?? true,
      metadata: Map<String, dynamic>.from(
        (json['metadata'] as Map?) ?? const {},
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      source: TeacherProfileMediaSource.fromJson(
        json['source'] is Map
            ? Map<String, dynamic>.from(json['source'] as Map)
            : null,
      ),
    );
  }

  final String id;
  final String teacherId;
  final TeacherProfileMediaKind mediaKind;
  final String? mediaId;
  final String? externalUrl;
  final String? title;
  final String? description;
  final String? coverMediaId;
  final String? coverImageUrl;
  final int position;
  final bool isPublished;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;
  final TeacherProfileMediaSource source;

  TeacherProfileMediaItem copyWith({
    int? position,
    bool? isPublished,
    String? title,
    String? description,
    String? coverMediaId,
    String? coverImageUrl,
    Map<String, dynamic>? metadata,
    String? externalUrl,
    TeacherProfileMediaSource? source,
  }) {
    return TeacherProfileMediaItem(
      id: id,
      teacherId: teacherId,
      mediaKind: mediaKind,
      mediaId: mediaId,
      externalUrl: externalUrl ?? this.externalUrl,
      title: title ?? this.title,
      description: description ?? this.description,
      coverMediaId: coverMediaId ?? this.coverMediaId,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      position: position ?? this.position,
      isPublished: isPublished ?? this.isPublished,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt,
      updatedAt: updatedAt,
      source: source ?? this.source,
    );
  }

  @override
  List<Object?> get props => [
    id,
    teacherId,
    mediaKind,
    mediaId,
    externalUrl,
    title,
    description,
    coverMediaId,
    coverImageUrl,
    position,
    isPublished,
    metadata,
    createdAt,
    updatedAt,
    source,
  ];
}

class TeacherProfileMediaPayload extends Equatable {
  const TeacherProfileMediaPayload({
    required this.items,
    required this.lessonMedia,
    required this.seminarRecordings,
  });

  factory TeacherProfileMediaPayload.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List? ?? const [];
    final lessonsJson = json['lesson_media'] as List? ?? const [];
    final recordingsJson = json['seminar_recordings'] as List? ?? const [];

    return TeacherProfileMediaPayload(
      items: itemsJson
          .whereType<Map>()
          .map(
            (e) =>
                TeacherProfileMediaItem.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
      lessonMedia: lessonsJson
          .whereType<Map>()
          .map(
            (e) => TeacherProfileLessonSource.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false),
      seminarRecordings: recordingsJson
          .whereType<Map>()
          .map(
            (e) => TeacherProfileRecordingSource.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false),
    );
  }

  static const empty = TeacherProfileMediaPayload(
    items: [],
    lessonMedia: [],
    seminarRecordings: [],
  );

  final List<TeacherProfileMediaItem> items;
  final List<TeacherProfileLessonSource> lessonMedia;
  final List<TeacherProfileRecordingSource> seminarRecordings;

  @override
  List<Object?> get props => [items, lessonMedia, seminarRecordings];
}
