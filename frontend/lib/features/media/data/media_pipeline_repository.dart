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

Object? _optionalResponseField(Object? payload, String key, String label) {
  switch (payload) {
    case final Map data:
      return data[key];
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

String _requiredResponseStringFrom(
  Object? payload,
  List<String> keys,
  String label,
  String fieldLabel,
) {
  switch (payload) {
    case final Map data:
      for (final key in keys) {
        if (!data.containsKey(key)) continue;
        final value = data[key];
        if (value is String && value.isNotEmpty) {
          return value;
        }
        throw StateError('$label field "$key" must be a non-empty string');
      }
      throw StateError('$label is missing required field: $fieldLabel');
    default:
      throw StateError('$label returned a non-object payload');
  }
}

String? _optionalResponseString(Object? payload, String key, String label) {
  final value = _optionalResponseField(payload, key, label);
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw StateError('$label field "$key" must be a string or null');
}

int? _optionalResponseInt(Object? payload, String key, String label) {
  final value = _optionalResponseField(payload, key, label);
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

  factory MediaUploadTarget.fromCanonicalMediaAssetResponse(Object? payload) =>
      MediaUploadTarget(
        mediaId: _requiredResponseString(
          payload,
          'media_asset_id',
          'MediaUploadTarget',
        ),
        uploadUrl: Uri.parse(
          _requiredResponseString(payload, 'upload_url', 'MediaUploadTarget'),
        ),
        objectPath: '',
        headers: _requiredResponseHeaders(
          payload,
          'headers',
          'MediaUploadTarget',
        ),
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
    mediaId: _requiredResponseStringFrom(
      payload,
      const ['media_id', 'media_asset_id'],
      'MediaStatus',
      'media_id/media_asset_id',
    ),
    state: _requiredResponseStringFrom(
      payload,
      const ['state', 'asset_state'],
      'MediaStatus',
      'state/asset_state',
    ),
    errorMessage: _optionalResponseString(
      payload,
      'error_message',
      'MediaStatus',
    ),
    ingestFormat: _optionalResponseString(
      payload,
      'ingest_format',
      'MediaStatus',
    ),
    streamingFormat: _optionalResponseString(
      payload,
      'streaming_format',
      'MediaStatus',
    ),
    durationSeconds: _optionalResponseInt(
      payload,
      'duration_seconds',
      'MediaStatus',
    ),
    codec: _optionalResponseString(payload, 'codec', 'MediaStatus'),
    lessonMediaId: _optionalResponseString(
      payload,
      'lesson_media_id',
      'MediaStatus',
    ),
    runtimeMediaId: _optionalResponseString(
      payload,
      'runtime_media_id',
      'MediaStatus',
    ),
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
      'Den här medieytan är inte monterad i den kanoniska frontendmodellen.';

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
    final response = await _client.raw.post<Object?>(
      '/api/media-assets/$mediaId/upload-completion',
      data: const <String, Object?>{},
    );
    return MediaStatus.fromResponse(response.data);
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
    final response = await _client.raw.post<Object?>(
      '/api/courses/$courseId/cover-media-assets/upload-url',
      data: <String, Object?>{
        'filename': filename,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
      },
    );
    return MediaUploadTarget.fromCanonicalMediaAssetResponse(response.data);
  }

  Future<void> clearCourseCover(String courseId) async {
    await _client.raw.patch<Object?>(
      '/studio/courses/$courseId',
      data: const <String, Object?>{'cover_media_id': null},
    );
  }

  Future<MediaStatus> fetchStatus(String mediaId) async {
    final response = await _client.raw.get<Object?>(
      '/api/media-assets/$mediaId/status',
    );
    return MediaStatus.fromResponse(response.data);
  }
}
