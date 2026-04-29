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
    required this.homeplayerLogo,
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
      homeplayerLogo: HomePlayerLogoSet.fromJson(
        _requiredMap(json['homeplayer_logo'], fieldName: 'homeplayer_logo'),
      ),
      textBundle: HomePlayerTextBundle.fromJson(json['text_bundle']),
    );
  }

  final List<HomeAudioFeedItem> items;
  final HomePlayerLogoSet homeplayerLogo;
  final HomePlayerTextBundle textBundle;

  @override
  List<Object?> get props => [items, homeplayerLogo, textBundle];
}

class HomePlayerLogoAsset extends Equatable {
  const HomePlayerLogoAsset({
    required this.assetKey,
    required this.resolvedUrl,
  });

  factory HomePlayerLogoAsset.fromJson(
    Map<String, dynamic> json, {
    required String expectedAssetKey,
  }) {
    final assetKey = (json['asset_key'] as String? ?? '').trim();
    if (assetKey != expectedAssetKey) {
      throw StateError('Invalid homeplayer logo asset_key: $assetKey');
    }
    final resolvedUrl = (json['resolved_url'] as String? ?? '').trim();
    if (resolvedUrl.isEmpty) {
      throw StateError('Missing homeplayer logo resolved_url: $assetKey');
    }
    return HomePlayerLogoAsset(assetKey: assetKey, resolvedUrl: resolvedUrl);
  }

  final String assetKey;
  final String resolvedUrl;

  @override
  List<Object?> get props => [assetKey, resolvedUrl];
}

class HomePlayerLogoSet extends Equatable {
  const HomePlayerLogoSet({required this.closed, required this.open});

  factory HomePlayerLogoSet.fromJson(Map<String, dynamic> json) {
    return HomePlayerLogoSet(
      closed: HomePlayerLogoAsset.fromJson(
        _requiredMap(json['closed'], fieldName: 'homeplayer_logo.closed'),
        expectedAssetKey: 'homeplayer_logo_closed',
      ),
      open: HomePlayerLogoAsset.fromJson(
        _requiredMap(json['open'], fieldName: 'homeplayer_logo.open'),
        expectedAssetKey: 'homeplayer_logo_open',
      ),
    );
  }

  final HomePlayerLogoAsset closed;
  final HomePlayerLogoAsset open;

  @override
  List<Object?> get props => [closed, open];
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
