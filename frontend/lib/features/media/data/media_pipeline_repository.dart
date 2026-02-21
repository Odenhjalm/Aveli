import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';

class MediaUploadTarget {
  const MediaUploadTarget({
    required this.mediaId,
    required this.uploadUrl,
    required this.objectPath,
    required this.headers,
    required this.expiresAt,
  });

  final String mediaId;
  final Uri uploadUrl;
  final String objectPath;
  final Map<String, String> headers;
  final DateTime expiresAt;

  factory MediaUploadTarget.fromJson(Map<String, dynamic> json) =>
      MediaUploadTarget(
        mediaId: json['media_id'] as String,
        uploadUrl: Uri.parse(json['upload_url'] as String),
        objectPath: json['object_path'] as String,
        headers: Map<String, String>.from(
          json['headers'] as Map<String, dynamic>? ?? const {},
        ),
        expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
      );
}

class MediaPlaybackUrl {
  const MediaPlaybackUrl({
    required this.playbackUrl,
    required this.expiresAt,
    required this.format,
  });

  final Uri playbackUrl;
  final DateTime expiresAt;
  final String format;

  factory MediaPlaybackUrl.fromJson(Map<String, dynamic> json) =>
      MediaPlaybackUrl(
        playbackUrl: Uri.parse(json['playback_url'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
        format: json['format'] as String? ?? 'mp3',
      );
}

class MediaStatus {
  const MediaStatus({
    required this.mediaId,
    required this.state,
    this.errorMessage,
    this.ingestFormat,
    this.streamingFormat,
    this.durationSeconds,
    this.codec,
  });

  final String mediaId;
  final String state;
  final String? errorMessage;
  final String? ingestFormat;
  final String? streamingFormat;
  final int? durationSeconds;
  final String? codec;

  factory MediaStatus.fromJson(Map<String, dynamic> json) => MediaStatus(
    mediaId: json['media_id'] as String,
    state: json['state'] as String? ?? 'uploaded',
    errorMessage: json['error_message'] as String?,
    ingestFormat: json['ingest_format'] as String?,
    streamingFormat: json['streaming_format'] as String?,
    durationSeconds: json['duration_seconds'] as int?,
    codec: json['codec'] as String?,
  );
}

class CoverMediaResponse {
  const CoverMediaResponse({required this.mediaId, required this.state});

  final String mediaId;
  final String state;

  factory CoverMediaResponse.fromJson(Map<String, dynamic> json) =>
      CoverMediaResponse(
        mediaId: json['media_id'] as String,
        state: json['state'] as String? ?? 'uploaded',
      );
}

class MediaPipelineRepository {
  MediaPipelineRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;
  static const String _homePlayerPurpose = 'home_player_audio';
  static const Set<String> _allowedPurposes = {
    'lesson_audio',
    _homePlayerPurpose,
  };

  static Map<String, dynamic> _buildUploadUrlPayload({
    required String filename,
    required String mimeType,
    required int sizeBytes,
    required String mediaType,
    String? purpose,
    String? courseId,
    String? lessonId,
  }) {
    final normalizedFilename = filename.trim();
    if (normalizedFilename.isEmpty) {
      throw ArgumentError.value(filename, 'filename', 'Must not be empty.');
    }

    final normalizedMimeType = mimeType.trim();
    if (normalizedMimeType.isEmpty) {
      throw ArgumentError.value(mimeType, 'mimeType', 'Must not be empty.');
    }

    if (sizeBytes <= 0) {
      throw ArgumentError.value(sizeBytes, 'sizeBytes', 'Must be > 0.');
    }

    final normalizedMediaType = mediaType.trim().toLowerCase();
    if (normalizedMediaType != 'audio') {
      throw ArgumentError.value(
        mediaType,
        'mediaType',
        'Unsupported mediaType for /api/media/upload-url (expected "audio").',
      );
    }

    final normalizedPurpose = purpose?.trim();
    if (normalizedPurpose != null && normalizedPurpose.isEmpty) {
      throw ArgumentError.value(
        purpose,
        'purpose',
        'If provided, purpose must not be empty.',
      );
    }
    if (normalizedPurpose != null &&
        !_allowedPurposes.contains(normalizedPurpose)) {
      throw ArgumentError.value(
        purpose,
        'purpose',
        'Unsupported purpose "$normalizedPurpose".',
      );
    }

    final normalizedCourseId = courseId?.trim();
    final normalizedLessonId = lessonId?.trim();
    final resolvedCourseId =
        normalizedCourseId == null || normalizedCourseId.isEmpty
        ? null
        : normalizedCourseId;
    final resolvedLessonId =
        normalizedLessonId == null || normalizedLessonId.isEmpty
        ? null
        : normalizedLessonId;

    if (normalizedPurpose == _homePlayerPurpose) {
      if (resolvedCourseId != null || resolvedLessonId != null) {
        throw ArgumentError(
          'courseId/lessonId must be omitted for home_player_audio uploads.',
        );
      }
    } else {
      if (resolvedCourseId == null && resolvedLessonId == null) {
        throw ArgumentError(
          'courseId or lessonId is required for lesson_audio uploads.',
        );
      }
    }

    return <String, dynamic>{
      'filename': normalizedFilename,
      'mime_type': normalizedMimeType,
      'size_bytes': sizeBytes,
      'media_type': 'audio',
      if (normalizedPurpose != null) 'purpose': normalizedPurpose,
      if (resolvedCourseId != null) 'course_id': resolvedCourseId,
      if (resolvedLessonId != null) 'lesson_id': resolvedLessonId,
    };
  }

  Future<MediaUploadTarget> requestUploadUrl({
    required String filename,
    required String mimeType,
    required int sizeBytes,
    required String mediaType,
    String? purpose,
    String? courseId,
    String? lessonId,
  }) async {
    final payload = _buildUploadUrlPayload(
      filename: filename,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      mediaType: mediaType,
      purpose: purpose,
      courseId: courseId,
      lessonId: lessonId,
    );
    final response = await _client.post<Map<String, dynamic>>(
      ApiPaths.mediaUploadUrl,
      body: payload,
    );
    return MediaUploadTarget.fromJson(response);
  }

  Future<MediaUploadTarget> refreshUploadUrl({required String mediaId}) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiPaths.mediaUploadUrlRefresh,
      body: {'media_id': mediaId},
    );
    return MediaUploadTarget.fromJson(response);
  }

  Future<MediaUploadTarget> requestCoverUploadUrl({
    required String filename,
    required String mimeType,
    required int sizeBytes,
    required String courseId,
  }) async {
    final payload = <String, dynamic>{
      'filename': filename,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'course_id': courseId,
    };
    final response = await _client.post<Map<String, dynamic>>(
      ApiPaths.mediaCoverUploadUrl,
      body: payload,
    );
    return MediaUploadTarget.fromJson(response);
  }

  Future<CoverMediaResponse> requestCoverFromLessonMedia({
    required String courseId,
    required String lessonMediaId,
  }) async {
    final payload = <String, dynamic>{
      'course_id': courseId,
      'lesson_media_id': lessonMediaId,
    };
    final response = await _client.post<Map<String, dynamic>>(
      ApiPaths.mediaCoverFromMedia,
      body: payload,
    );
    return CoverMediaResponse.fromJson(response);
  }

  Future<void> clearCourseCover(String courseId) async {
    await _client.post<void>(
      ApiPaths.mediaCoverClear,
      body: {'course_id': courseId},
    );
  }

  Future<MediaStatus> fetchStatus(String mediaId) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiPaths.mediaStatus(mediaId),
    );
    return MediaStatus.fromJson(response);
  }

  Future<MediaPlaybackUrl> fetchPlaybackUrl(String mediaId) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiPaths.mediaPlaybackUrl,
      body: {'media_id': mediaId},
    );
    return MediaPlaybackUrl.fromJson(response);
  }

  Future<String> fetchLessonPlaybackUrl(String lessonMediaId) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiPaths.mediaLessonPlaybackUrl,
      body: {'lesson_media_id': lessonMediaId},
    );
    final rawUrl = response['url'] as String?;
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      throw const FormatException('Playback URL saknas');
    }
    return rawUrl;
  }
}
