import 'package:aveli/api/api_client.dart';
import 'package:dio/dio.dart';

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

class MediaUploadTarget {
  const MediaUploadTarget({
    required this.mediaId,
    required this.uploadSessionId,
    required this.uploadEndpoint,
    required this.expiresAt,
    this.sessionStatusEndpoint,
    this.finalizeEndpoint,
    this.chunkUploadUrlTemplate,
    this.chunkSize,
    this.expectedChunks,
  });

  final String mediaId;
  final String uploadSessionId;
  final String uploadEndpoint;
  final DateTime expiresAt;
  final String? sessionStatusEndpoint;
  final String? finalizeEndpoint;
  final String? chunkUploadUrlTemplate;
  final int? chunkSize;
  final int? expectedChunks;

  factory MediaUploadTarget.fromResponse(Object? payload) => MediaUploadTarget(
    mediaId: _requiredResponseString(payload, 'media_id', 'MediaUploadTarget'),
    uploadSessionId: _requiredResponseString(
      payload,
      'upload_session_id',
      'MediaUploadTarget',
    ),
    uploadEndpoint: _requiredResponseString(
      payload,
      'upload_endpoint',
      'MediaUploadTarget',
    ),
    expiresAt: _requiredResponseUtcDateTime(
      payload,
      'expires_at',
      'MediaUploadTarget',
    ),
    sessionStatusEndpoint: _optionalResponseString(
      payload,
      'session_status_endpoint',
      'MediaUploadTarget',
    ),
    finalizeEndpoint: _optionalResponseString(
      payload,
      'finalize_endpoint',
      'MediaUploadTarget',
    ),
    chunkUploadUrlTemplate: _optionalResponseString(
      payload,
      'chunk_upload_url_template',
      'MediaUploadTarget',
    ),
    chunkSize: _optionalResponseInt(payload, 'chunk_size', 'MediaUploadTarget'),
    expectedChunks: _optionalResponseInt(
      payload,
      'expected_chunks',
      'MediaUploadTarget',
    ),
  );

  factory MediaUploadTarget.fromCanonicalMediaAssetResponse(Object? payload) {
    final uploadEndpoint = _requiredResponseStringFrom(
      payload,
      const ['upload_endpoint', 'chunk_upload_url_template'],
      'MediaUploadTarget',
      'upload_endpoint/chunk_upload_url_template',
    );
    final explicitTemplate = _optionalResponseString(
      payload,
      'chunk_upload_url_template',
      'MediaUploadTarget',
    );
    return MediaUploadTarget(
      mediaId: _requiredResponseString(
        payload,
        'media_asset_id',
        'MediaUploadTarget',
      ),
      uploadSessionId: _requiredResponseString(
        payload,
        'upload_session_id',
        'MediaUploadTarget',
      ),
      uploadEndpoint: uploadEndpoint,
      expiresAt: _requiredResponseUtcDateTime(
        payload,
        'expires_at',
        'MediaUploadTarget',
      ),
      sessionStatusEndpoint: _optionalResponseString(
        payload,
        'session_status_endpoint',
        'MediaUploadTarget',
      ),
      finalizeEndpoint: _optionalResponseString(
        payload,
        'finalize_endpoint',
        'MediaUploadTarget',
      ),
      chunkUploadUrlTemplate:
          explicitTemplate ??
          (uploadEndpoint.contains('{') ? uploadEndpoint : null),
      chunkSize: _optionalResponseInt(
        payload,
        'chunk_size',
        'MediaUploadTarget',
      ),
      expectedChunks: _optionalResponseInt(
        payload,
        'expected_chunks',
        'MediaUploadTarget',
      ),
    );
  }

  bool get hasHomePlayerChunkSession {
    final endpoint = uploadEndpoint.trim();
    final finalize = finalizeEndpoint?.trim() ?? '';
    return uploadSessionId.trim().isNotEmpty &&
        endpoint.isNotEmpty &&
        finalize.isNotEmpty &&
        (chunkSize ?? 0) > 0 &&
        (expectedChunks ?? 0) > 0 &&
        !endpoint.endsWith('/upload-bytes');
  }

  String chunkUploadEndpoint(int chunkIndex) {
    if (chunkIndex < 0) {
      throw RangeError.value(chunkIndex, 'chunkIndex');
    }
    final template = chunkUploadUrlTemplate?.trim();
    if (template != null && template.isNotEmpty) {
      if (template.contains('{chunk_index}')) {
        return template.replaceAll('{chunk_index}', '$chunkIndex');
      }
      if (template.contains('{index}')) {
        return template.replaceAll('{index}', '$chunkIndex');
      }
      if (template.endsWith('/$chunkIndex')) {
        return template;
      }
    }
    final base = uploadEndpoint.endsWith('/')
        ? uploadEndpoint.substring(0, uploadEndpoint.length - 1)
        : uploadEndpoint;
    return '$base/$chunkIndex';
  }
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
    if (purpose == 'home_player_audio') {
      final response = await _client.raw.post<Object?>(
        '/api/home-player/media-assets/upload-url',
        data: <String, Object?>{
          'filename': filename,
          'mime_type': mimeType,
          'size_bytes': sizeBytes,
        },
      );
      return MediaUploadTarget.fromCanonicalMediaAssetResponse(response.data);
    }
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

  Uri resolveUploadEndpoint(MediaUploadTarget target) {
    return _client.resolveUri(target.uploadEndpoint);
  }

  Uri resolveEndpoint(String endpoint) {
    return _client.resolveUri(endpoint);
  }

  Future<Map<String, String>> uploadHeaders(MediaUploadTarget target) {
    return uploadSessionHeaders(
      endpoint: target.uploadEndpoint,
      uploadSessionId: target.uploadSessionId,
    );
  }

  Future<Map<String, String>> uploadSessionHeaders({
    required String endpoint,
    required String uploadSessionId,
    String method = 'PUT',
    Map<String, String> headers = const <String, String>{},
  }) {
    return _client.authenticatedHeadersFor(
      endpoint,
      method: method,
      headers: <String, String>{
        ...headers,
        'X-Aveli-Upload-Session': uploadSessionId,
      },
    );
  }

  Future<MediaStatus> finalizeHomePlayerUpload({
    required MediaUploadTarget target,
  }) async {
    final endpoint = target.finalizeEndpoint?.trim();
    if (endpoint == null || endpoint.isEmpty) {
      throw StateError('home_player_upload_finalize_endpoint_missing');
    }
    final response = await _client.raw.post<Object?>(
      endpoint,
      data: const <String, Object?>{},
    );
    return MediaStatus.fromResponse(response.data);
  }
}

extension MediaPipelineUploadBytes on MediaPipelineRepository {
  Future<void> uploadBytes({
    required MediaUploadTarget target,
    required Object data,
    required String contentType,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    await _client.raw.put<Object?>(
      target.uploadEndpoint,
      data: data,
      options: Options(
        contentType: contentType,
        headers: <String, Object?>{
          'X-Aveli-Upload-Session': target.uploadSessionId,
        },
      ),
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }
}
