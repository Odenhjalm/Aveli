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

class HomePlayerCatalogTextValue extends Equatable {
  const HomePlayerCatalogTextValue({
    required this.surfaceId,
    required this.textId,
    required this.authorityClass,
    required this.canonicalOwner,
    required this.sourceContract,
    required this.backendNamespace,
    required this.apiSurface,
    required this.deliverySurface,
    required this.renderSurface,
    required this.language,
    required this.value,
    this.interpolationKeys = const <String>[],
    this.forbiddenRenderFields = const <String>[],
  });

  factory HomePlayerCatalogTextValue.fromJson(Map<String, dynamic> json) {
    return HomePlayerCatalogTextValue(
      surfaceId: (json['surface_id'] as String? ?? '').trim(),
      textId: (json['text_id'] as String? ?? '').trim(),
      authorityClass: (json['authority_class'] as String? ?? '').trim(),
      canonicalOwner: (json['canonical_owner'] as String? ?? '').trim(),
      sourceContract: (json['source_contract'] as String? ?? '').trim(),
      backendNamespace: (json['backend_namespace'] as String? ?? '').trim(),
      apiSurface: (json['api_surface'] as String? ?? '').trim(),
      deliverySurface: (json['delivery_surface'] as String? ?? '').trim(),
      renderSurface: (json['render_surface'] as String? ?? '').trim(),
      language: (json['language'] as String? ?? '').trim(),
      value: (json['value'] as String? ?? '').trim(),
      interpolationKeys: (json['interpolation_keys'] as List? ?? const [])
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      forbiddenRenderFields:
          (json['forbidden_render_fields'] as List? ?? const [])
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false),
    );
  }

  final String surfaceId;
  final String textId;
  final String authorityClass;
  final String canonicalOwner;
  final String sourceContract;
  final String backendNamespace;
  final String apiSurface;
  final String deliverySurface;
  final String renderSurface;
  final String language;
  final String value;
  final List<String> interpolationKeys;
  final List<String> forbiddenRenderFields;

  @override
  List<Object?> get props => [
    surfaceId,
    textId,
    authorityClass,
    canonicalOwner,
    sourceContract,
    backendNamespace,
    apiSurface,
    deliverySurface,
    renderSurface,
    language,
    value,
    interpolationKeys,
    forbiddenRenderFields,
  ];
}

class HomePlayerTextBundle extends Equatable {
  const HomePlayerTextBundle({this.entries = const {}});

  factory HomePlayerTextBundle.fromJson(Object? payload) {
    if (payload is! Map) return const HomePlayerTextBundle();
    final entries = <String, HomePlayerCatalogTextValue>{};
    for (final entry in payload.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! Map) continue;
      entries[key] = HomePlayerCatalogTextValue.fromJson(
        Map<String, dynamic>.from(value),
      );
    }
    return HomePlayerTextBundle(entries: Map.unmodifiable(entries));
  }

  final Map<String, HomePlayerCatalogTextValue> entries;

  HomePlayerCatalogTextValue require(String textId) {
    final entry = entries[textId];
    if (entry == null) {
      throw StateError('Missing canonical home player text: $textId');
    }
    return entry;
  }

  String requireValue(String textId) => require(textId).value;

  @override
  List<Object?> get props => [entries];
}

class HomePlayerUploadItem extends Equatable {
  const HomePlayerUploadItem({
    required this.id,
    this.mediaId,
    this.mediaAssetId,
    required this.title,
    required this.kind,
    required this.active,
    this.createdAt,
    this.originalName,
    this.contentType,
    this.byteSize,
    this.mediaState,
    this.mediaErrorMessage,
  });

  factory HomePlayerUploadItem.fromJson(Map<String, dynamic> json) {
    return HomePlayerUploadItem(
      id: json['id'] as String,
      mediaId: json['media_id'] as String?,
      mediaAssetId: json['media_asset_id'] as String?,
      title: (json['title'] as String? ?? '').trim(),
      kind: (json['kind'] as String? ?? 'audio').trim(),
      active: json['active'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      originalName: json['original_name'] as String?,
      contentType: json['content_type'] as String?,
      byteSize: json['byte_size'] as int?,
      mediaState: json['media_state'] as String?,
      mediaErrorMessage: json['media_error_message'] as String?,
    );
  }

  final String id;
  final String? mediaId;
  final String? mediaAssetId;
  final String title;
  final String kind;
  final bool active;
  final DateTime? createdAt;
  final String? originalName;
  final String? contentType;
  final int? byteSize;
  final String? mediaState;
  final String? mediaErrorMessage;

  HomePlayerUploadItem copyWith({bool? active, String? title}) {
    return HomePlayerUploadItem(
      id: id,
      mediaId: mediaId,
      mediaAssetId: mediaAssetId,
      title: title ?? this.title,
      kind: kind,
      active: active ?? this.active,
      createdAt: createdAt,
      originalName: originalName,
      contentType: contentType,
      byteSize: byteSize,
      mediaState: mediaState,
      mediaErrorMessage: mediaErrorMessage,
    );
  }

  @override
  List<Object?> get props => [
    id,
    mediaId,
    mediaAssetId,
    title,
    kind,
    active,
    createdAt,
    originalName,
    contentType,
    byteSize,
    mediaState,
    mediaErrorMessage,
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
    this.textBundle = const HomePlayerTextBundle(),
  });

  factory HomePlayerLibraryPayload.fromJson(Map<String, dynamic> json) {
    final uploadsJson = json['uploads'] as List? ?? const [];
    final linksJson = json['course_links'] as List? ?? const [];
    final sourcesJson = json['course_media'] as List? ?? const [];
    return HomePlayerLibraryPayload(
      uploads: uploadsJson
          .whereType<Map>()
          .map(
            (e) => HomePlayerUploadItem.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
      courseLinks: linksJson
          .whereType<Map>()
          .map(
            (e) =>
                HomePlayerCourseLinkItem.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
      courseMedia: sourcesJson
          .whereType<Map>()
          .map(
            (e) => TeacherProfileLessonSource.fromResponse(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false),
      textBundle: HomePlayerTextBundle.fromJson(json['text_bundle']),
    );
  }

  final List<HomePlayerUploadItem> uploads;
  final List<HomePlayerCourseLinkItem> courseLinks;
  final List<TeacherProfileLessonSource> courseMedia;
  final HomePlayerTextBundle textBundle;

  @override
  List<Object?> get props => [uploads, courseLinks, courseMedia, textBundle];
}
