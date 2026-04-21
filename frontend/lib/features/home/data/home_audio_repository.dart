import 'package:equatable/equatable.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/shared/utils/resolved_media_contract.dart';

enum HomeAudioSourceType {
  directUpload('direct_upload'),
  courseLink('course_link');

  const HomeAudioSourceType(this.apiValue);

  final String apiValue;

  static HomeAudioSourceType fromApi(String value) {
    return HomeAudioSourceType.values.firstWhere(
      (sourceType) => sourceType.apiValue == value,
      orElse: () => HomeAudioSourceType.directUpload,
    );
  }
}

class HomeAudioFeedItem extends Equatable {
  const HomeAudioFeedItem({
    required this.sourceType,
    required this.title,
    required this.teacherId,
    required this.createdAt,
    required this.media,
    this.lessonTitle,
    this.courseId,
    this.courseTitle,
    this.courseSlug,
    this.teacherName,
  });

  factory HomeAudioFeedItem.fromJson(Map<String, dynamic> json) {
    _assertNoForbiddenHomeAudioFields(json);
    final media = _requiredMap(json['media'], fieldName: 'media');
    _assertNoForbiddenHomeAudioMediaFields(media);
    return HomeAudioFeedItem(
      sourceType: HomeAudioSourceType.fromApi(
        (json['source_type'] as String? ?? '').trim(),
      ),
      title: (json['title'] as String? ?? '').trim(),
      lessonTitle: (json['lesson_title'] as String?)?.trim(),
      courseId: (json['course_id'] as String?)?.trim(),
      courseTitle: (json['course_title'] as String?)?.trim(),
      courseSlug: (json['course_slug'] as String?)?.trim(),
      teacherId: (json['teacher_id'] as String? ?? '').trim(),
      teacherName: (json['teacher_name'] as String?)?.trim(),
      createdAt: DateTime.parse((json['created_at'] as String? ?? '').trim()),
      media: ResolvedMediaData.fromJson(media),
    );
  }

  final HomeAudioSourceType sourceType;
  final String title;
  final String? lessonTitle;
  final String? courseId;
  final String? courseTitle;
  final String? courseSlug;
  final String teacherId;
  final String? teacherName;
  final DateTime createdAt;
  final ResolvedMediaData media;

  bool get isReady =>
      media.state.trim().toLowerCase() == 'ready' &&
      (media.resolvedUrl?.trim().isNotEmpty ?? false);

  @override
  List<Object?> get props => [
    sourceType,
    title,
    lessonTitle,
    courseId,
    courseTitle,
    courseSlug,
    teacherId,
    teacherName,
    createdAt,
    media.mediaId,
    media.state,
    media.resolvedUrl,
  ];
}

class HomeAudioFeedPayload extends Equatable {
  const HomeAudioFeedPayload({
    this.items = const [],
    this.textBundle = const HomePlayerTextBundle(),
  });

  factory HomeAudioFeedPayload.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List? ?? const [];
    return HomeAudioFeedPayload(
      items: itemsJson
          .whereType<Map>()
          .map(
            (item) =>
                HomeAudioFeedItem.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      textBundle: HomePlayerTextBundle.fromJson(json['text_bundle']),
    );
  }

  final List<HomeAudioFeedItem> items;
  final HomePlayerTextBundle textBundle;

  @override
  List<Object?> get props => [items, textBundle];
}

class HomeAudioRepository {
  HomeAudioRepository(this._client);

  final ApiClient _client;

  Future<HomeAudioFeedPayload> fetchHomeAudio({int limit = 12}) async {
    final response = await _client.raw.get<Object?>(
      '/home/audio',
      queryParameters: <String, Object?>{'limit': limit},
    );
    return HomeAudioFeedPayload.fromJson(
      _requiredMap(response.data, fieldName: 'Home audio feed'),
    );
  }
}

Map<String, dynamic> _requiredMap(Object? value, {required String fieldName}) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw StateError('Invalid $fieldName payload');
}

void _assertNoForbiddenHomeAudioFields(Map<String, dynamic> json) {
  const forbiddenFields = <String>{
    'runtime_media_id',
    'is_playable',
    'playback_state',
    'failure_reason',
    'media_asset_id',
    'media_id',
    'storage_bucket',
    'storage_path',
    'playback_object_path',
    'playback_format',
    'signed_url',
    'download_url',
    'upload_url',
  };
  final conflicts = json.keys.toSet().intersection(forbiddenFields);
  if (conflicts.isNotEmpty) {
    throw StateError(
      'Home audio contract violation: forbidden fields present: '
      '${conflicts.toList()..sort()}',
    );
  }
}

void _assertNoForbiddenHomeAudioMediaFields(Map<String, dynamic> json) {
  const forbiddenFields = <String>{
    'media_asset_id',
    'signed_url',
    'download_url',
    'storage_path',
    'playback_object_path',
    'playback_format',
    'streaming_format',
    'object_path',
  };
  final conflicts = json.keys.toSet().intersection(forbiddenFields);
  if (conflicts.isNotEmpty) {
    throw StateError(
      'Home audio media contract violation: forbidden fields present: '
      '${conflicts.toList()..sort()}',
    );
  }
}
