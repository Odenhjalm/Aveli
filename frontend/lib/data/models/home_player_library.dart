import 'package:equatable/equatable.dart';

import 'teacher_profile_media.dart';

enum HomePlayerCourseLinkStatus {
  active('active'),
  sourceMissing('source_missing'),
  courseUnpublished('course_unpublished');

  const HomePlayerCourseLinkStatus(this.apiValue);

  final String apiValue;

  static HomePlayerCourseLinkStatus fromApi(String value) {
    return HomePlayerCourseLinkStatus.values.firstWhere(
      (status) => status.apiValue == value,
      orElse: () => HomePlayerCourseLinkStatus.sourceMissing,
    );
  }
}

class HomePlayerUploadItem extends Equatable {
  const HomePlayerUploadItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.active,
    this.createdAt,
    this.originalName,
    this.contentType,
    this.byteSize,
  });

  factory HomePlayerUploadItem.fromJson(Map<String, dynamic> json) {
    return HomePlayerUploadItem(
      id: json['id'] as String,
      title: (json['title'] as String? ?? '').trim(),
      kind: (json['kind'] as String? ?? 'audio').trim(),
      active: json['active'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      originalName: json['original_name'] as String?,
      contentType: json['content_type'] as String?,
      byteSize: json['byte_size'] as int?,
    );
  }

  final String id;
  final String title;
  final String kind;
  final bool active;
  final DateTime? createdAt;
  final String? originalName;
  final String? contentType;
  final int? byteSize;

  HomePlayerUploadItem copyWith({bool? active, String? title}) {
    return HomePlayerUploadItem(
      id: id,
      title: title ?? this.title,
      kind: kind,
      active: active ?? this.active,
      createdAt: createdAt,
      originalName: originalName,
      contentType: contentType,
      byteSize: byteSize,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    kind,
    active,
    createdAt,
    originalName,
    contentType,
    byteSize,
  ];
}

class HomePlayerCourseLinkItem extends Equatable {
  const HomePlayerCourseLinkItem({
    required this.id,
    required this.title,
    required this.courseTitle,
    required this.enabled,
    required this.status,
    this.kind,
    this.lessonMediaId,
    this.createdAt,
  });

  factory HomePlayerCourseLinkItem.fromJson(Map<String, dynamic> json) {
    return HomePlayerCourseLinkItem(
      id: json['id'] as String,
      title: (json['title'] as String? ?? '').trim(),
      courseTitle: (json['course_title'] as String? ?? '').trim(),
      enabled: json['enabled'] as bool? ?? false,
      status: HomePlayerCourseLinkStatus.fromApi(
        (json['status'] as String? ?? '').trim(),
      ),
      kind: (json['kind'] as String?)?.trim(),
      lessonMediaId: json['lesson_media_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  final String id;
  final String title;
  final String courseTitle;
  final bool enabled;
  final HomePlayerCourseLinkStatus status;
  final String? kind;
  final String? lessonMediaId;
  final DateTime? createdAt;

  HomePlayerCourseLinkItem copyWith({bool? enabled}) {
    return HomePlayerCourseLinkItem(
      id: id,
      title: title,
      courseTitle: courseTitle,
      enabled: enabled ?? this.enabled,
      status: status,
      kind: kind,
      lessonMediaId: lessonMediaId,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    courseTitle,
    enabled,
    status,
    kind,
    lessonMediaId,
    createdAt,
  ];
}

class HomePlayerLibraryPayload extends Equatable {
  const HomePlayerLibraryPayload({
    this.uploads = const [],
    this.courseLinks = const [],
    this.courseMedia = const [],
  });

  factory HomePlayerLibraryPayload.fromJson(Map<String, dynamic> json) {
    final uploadsJson = json['uploads'] as List? ?? const [];
    final linksJson = json['course_links'] as List? ?? const [];
    final sourcesJson = json['course_media'] as List? ?? const [];
    return HomePlayerLibraryPayload(
      uploads: uploadsJson
          .whereType<Map>()
          .map((e) => HomePlayerUploadItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      courseLinks: linksJson
          .whereType<Map>()
          .map(
            (e) => HomePlayerCourseLinkItem.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false),
      courseMedia: sourcesJson
          .whereType<Map>()
          .map(
            (e) => TeacherProfileLessonSource.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false),
    );
  }

  final List<HomePlayerUploadItem> uploads;
  final List<HomePlayerCourseLinkItem> courseLinks;
  final List<TeacherProfileLessonSource> courseMedia;

  @override
  List<Object?> get props => [uploads, courseLinks, courseMedia];
}

