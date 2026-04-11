import 'package:aveli/api/api_client.dart';
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

class CanonicalMediaSurfaceUnavailable implements Exception {
  const CanonicalMediaSurfaceUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

class MediaPipelineRepository {
  MediaPipelineRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;
  static const _surfaceUnavailable =
      'Den har medieytan ar inte monterad i den kanoniska frontendmodellen.';

  Never _unavailable() {
    final _ = _client;
    throw const CanonicalMediaSurfaceUnavailable(_surfaceUnavailable);
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
    _unavailable();
  }

  Future<MediaUploadTarget> refreshUploadUrl({required String mediaId}) async {
    _unavailable();
  }

  Future<MediaStatus> completeUpload({required String mediaId}) async {
    _unavailable();
  }

  Future<MediaStatus> attachUpload({
    required String mediaId,
    required String linkScope,
    String? lessonId,
    String? lessonMediaId,
  }) async {
    _unavailable();
  }

  Future<MediaUploadTarget> requestCoverUploadUrl({
    required String filename,
    required String mimeType,
    required int sizeBytes,
    required String courseId,
  }) async {
    _unavailable();
  }

  Future<CoverMediaResponse> requestCoverFromLessonMedia({
    required String courseId,
    required String lessonMediaId,
  }) async {
    _unavailable();
  }

  Future<void> clearCourseCover(String courseId) async {
    _unavailable();
  }

  Future<MediaStatus> fetchStatus(String mediaId) async {
    _unavailable();
  }
}
