import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/shared/models/request_headers.dart';

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

DateTime _requiredResponseUtcDateTime(
  Object? payload,
  String key,
  String label,
) {
  final value = _requireResponseField(payload, key, label);
  if (value is! String || value.isEmpty) {
    throw StateError('$label field "$key" must be an ISO datetime string');
  }
  return DateTime.parse(value).toUtc();
}

RequestHeaders _requiredResponseHeaders(
  Object? payload,
  String key,
  String label,
) {
  return RequestHeaders.fromResponseObject(
    _requireResponseField(payload, key, label),
    label: '$label field "$key"',
  );
}

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
  final RequestHeaders headers;
  final DateTime expiresAt;

  factory MediaUploadTarget.fromResponse(Object? payload) => MediaUploadTarget(
    mediaId: _requiredResponseString(payload, 'media_id', 'MediaUploadTarget'),
    uploadUrl: Uri.parse(
      _requiredResponseString(payload, 'upload_url', 'MediaUploadTarget'),
    ),
    objectPath: _requiredResponseString(
      payload,
      'object_path',
      'MediaUploadTarget',
    ),
    headers: _requiredResponseHeaders(payload, 'headers', 'MediaUploadTarget'),
    expiresAt: _requiredResponseUtcDateTime(
      payload,
      'expires_at',
      'MediaUploadTarget',
    ),
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
    this.lessonMediaId,
    this.runtimeMediaId,
  });

  final String mediaId;
  final String state;
  final String? errorMessage;
  final String? ingestFormat;
  final String? streamingFormat;
  final int? durationSeconds;
  final String? codec;
  final String? lessonMediaId;
  final String? runtimeMediaId;

  factory MediaStatus.fromResponse(Object? payload) => MediaStatus(
    mediaId: _requiredResponseString(payload, 'media_id', 'MediaStatus'),
    state: _requiredResponseString(payload, 'state', 'MediaStatus'),
    errorMessage: _nullableResponseString(
      payload,
      'error_message',
      'MediaStatus',
    ),
    ingestFormat: _nullableResponseString(
      payload,
      'ingest_format',
      'MediaStatus',
    ),
    streamingFormat: _nullableResponseString(
      payload,
      'streaming_format',
      'MediaStatus',
    ),
    durationSeconds: _nullableResponseInt(
      payload,
      'duration_seconds',
      'MediaStatus',
    ),
    codec: _nullableResponseString(payload, 'codec', 'MediaStatus'),
    lessonMediaId: _nullableResponseString(
      payload,
      'lesson_media_id',
      'MediaStatus',
    ),
    runtimeMediaId: _nullableResponseString(
      payload,
      'runtime_media_id',
      'MediaStatus',
    ),
  );
}

class CoverMediaResponse {
  const CoverMediaResponse({required this.mediaId, required this.state});

  final String mediaId;
  final String state;

  factory CoverMediaResponse.fromResponse(Object? payload) =>
      CoverMediaResponse(
        mediaId: _requiredResponseString(
          payload,
          'media_id',
          'CoverMediaResponse',
        ),
        state: _requiredResponseString(payload, 'state', 'CoverMediaResponse'),
      );
}

class MediaPipelineRepository {
  MediaPipelineRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;
  static const String _homePlayerPurpose = 'home_player_audio';
  static const Set<String> _allowedPurposes = {_homePlayerPurpose};

  static Map<String, dynamic> _buildUploadUrlPayload({
    required String filename,
    required String mimeType,
    required int sizeBytes,
    required String mediaType,
    String? purpose,
    String? courseId,
    String? lessonId,
  }) {
    if (filename.isEmpty) {
      throw ArgumentError.value(filename, 'filename', 'Must not be empty.');
    }

    if (mimeType.isEmpty) {
      throw ArgumentError.value(mimeType, 'mimeType', 'Must not be empty.');
    }

    if (sizeBytes <= 0) {
      throw ArgumentError.value(sizeBytes, 'sizeBytes', 'Must be > 0.');
    }

    if (mediaType != 'audio' &&
        mediaType != 'image' &&
        mediaType != 'video' &&
        mediaType != 'document') {
      throw ArgumentError.value(
        mediaType,
        'mediaType',
        'Unsupported mediaType for media upload.',
      );
    }

    if (purpose != null && purpose.isEmpty) {
      throw ArgumentError.value(
        purpose,
        'purpose',
        'If provided, purpose must not be empty.',
      );
    }
    if (purpose != null && !_allowedPurposes.contains(purpose)) {
      throw ArgumentError.value(
        purpose,
        'purpose',
        'Unsupported purpose "$purpose".',
      );
    }

    if (courseId != null && courseId.isEmpty) {
      throw ArgumentError.value(
        courseId,
        'courseId',
        'If provided, courseId must not be empty.',
      );
    }
    if (lessonId != null && lessonId.isEmpty) {
      throw ArgumentError.value(
        lessonId,
        'lessonId',
        'If provided, lessonId must not be empty.',
      );
    }

    if (lessonId != null || courseId != null) {
      throw ArgumentError(
        'Lesson media uploads use StudioRepository.uploadLessonMedia.',
      );
    }

    if (mediaType == 'audio') {
      if (purpose != _homePlayerPurpose) {
        throw ArgumentError.value(
          purpose,
          'purpose',
          'purpose must be home_player_audio for this upload surface.',
        );
      }
    } else {
      throw ArgumentError(
        'Non-audio lesson media uploads use StudioRepository.uploadLessonMedia.',
      );
    }

    return <String, dynamic>{
      'filename': filename,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'media_type': mediaType,
      if (purpose != null) 'purpose': purpose,
      if (courseId != null) 'course_id': courseId,
      if (lessonId != null) 'lesson_id': lessonId,
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
    final response = await _client.post<Object?>(
      ApiPaths.mediaUploadUrl,
      body: payload,
    );
    return MediaUploadTarget.fromResponse(response);
  }

  Future<MediaUploadTarget> refreshUploadUrl({required String mediaId}) async {
    final response = await _client.post<Object?>(
      ApiPaths.mediaUploadUrlRefresh,
      body: {'media_id': mediaId},
    );
    return MediaUploadTarget.fromResponse(response);
  }

  Future<MediaStatus> completeUpload({required String mediaId}) async {
    final response = await _client.post<Object?>(
      ApiPaths.mediaComplete,
      body: {'media_id': mediaId},
    );
    return MediaStatus.fromResponse(response);
  }

  Future<MediaStatus> attachUpload({
    required String mediaId,
    required String linkScope,
    String? lessonId,
    String? lessonMediaId,
  }) async {
    throw UnsupportedError(
      'Lesson media attachments use canonical media placement endpoints.',
    );
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
    final response = await _client.post<Object?>(
      ApiPaths.mediaCoverUploadUrl,
      body: payload,
    );
    return MediaUploadTarget.fromResponse(response);
  }

  Future<CoverMediaResponse> requestCoverFromLessonMedia({
    required String courseId,
    required String lessonMediaId,
  }) async {
    final payload = <String, dynamic>{
      'course_id': courseId,
      'lesson_media_id': lessonMediaId,
    };
    final response = await _client.post<Object?>(
      ApiPaths.mediaCoverFromMedia,
      body: payload,
    );
    return CoverMediaResponse.fromResponse(response);
  }

  Future<void> clearCourseCover(String courseId) async {
    await _client.post<void>(
      ApiPaths.mediaCoverClear,
      body: {'course_id': courseId},
    );
  }

  Future<MediaStatus> fetchStatus(String mediaId) async {
    final response = await _client.get<Object?>(ApiPaths.mediaStatus(mediaId));
    return MediaStatus.fromResponse(response);
  }
}
