import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/auth_repository.dart';

class HomeAudioItem {
  HomeAudioItem({
    required this.id,
    required this.lessonId,
    required this.lessonTitle,
    required this.courseId,
    required this.courseTitle,
    this.courseSlug,
    required this.kind,
    this.durationSeconds,
    this.createdAt,
    this.contentType,
    this.byteSize,
    this.originalName,
    this.isIntro,
    this.isFreeIntro,
    this.streamingFormat,
    this.codec,
    this.runtimeMediaId,
    this.isPlayable = false,
    this.playbackState,
    this.failureReason,
  });

  final String id;
  final String lessonId;
  final String lessonTitle;
  final String courseId;
  final String courseTitle;
  final String? courseSlug;
  final String kind;
  final int? durationSeconds;
  final DateTime? createdAt;
  final String? contentType;
  final int? byteSize;
  final String? originalName;
  final bool? isIntro;
  final bool? isFreeIntro;
  final String? streamingFormat;
  final String? codec;
  final String? runtimeMediaId;
  final bool isPlayable;
  final String? playbackState;
  final String? failureReason;

  String get displayTitle {
    if (lessonTitle.trim().isNotEmpty) return lessonTitle.trim();
    if ((originalName ?? '').trim().isNotEmpty) return originalName!.trim();
    return 'Ljudspår';
  }

  factory HomeAudioItem.fromJson(Map<String, dynamic> json) => HomeAudioItem(
    id: json['id'] as String,
    lessonId: json['lesson_id'] as String,
    lessonTitle: (json['lesson_title'] ?? '') as String,
    courseId: json['course_id'] as String,
    courseTitle: (json['course_title'] ?? '') as String,
    courseSlug: json['course_slug'] as String?,
    kind: (json['kind'] ?? 'audio') as String,
    durationSeconds: _asInt(json['duration_seconds']),
    createdAt: _parseDate(json['created_at']),
    contentType: json['content_type'] as String?,
    byteSize: _asInt(json['byte_size']),
    originalName: json['original_name'] as String?,
    isIntro: json['is_intro'] as bool?,
    isFreeIntro: json['is_free_intro'] as bool?,
    streamingFormat: json['streaming_format'] as String?,
    codec: json['codec'] as String?,
    runtimeMediaId: json['runtime_media_id'] as String?,
    isPlayable: json['is_playable'] == true,
    playbackState: json['playback_state'] as String?,
    failureReason: json['failure_reason'] as String?,
  );

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}

class HomeAudioRepository {
  HomeAudioRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<List<HomeAudioItem>> fetchHomeAudio({int limit = 12}) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/home/audio',
      queryParameters: {'limit': limit},
    );
    final items = response['items'] as List? ?? const [];
    return items
        .map(
          (item) =>
              HomeAudioItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }
}

final homeAudioRepositoryProvider = Provider<HomeAudioRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return HomeAudioRepository(client: client);
});
