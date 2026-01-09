import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/errors/app_failure.dart';

class PresignedMedia {
  PresignedMedia({
    required this.url,
    required this.headers,
    required this.expiresAt,
  });

  final Uri url;
  final Map<String, String> headers;
  final DateTime expiresAt;
}

class PresignedUploadTarget {
  const PresignedUploadTarget({
    required this.url,
    required this.headers,
    required this.method,
    this.storagePath,
    this.storageBucket,
  });

  final Uri url;
  final Map<String, String> headers;
  final String method;
  final String? storagePath;
  final String? storageBucket;
}

class MediaService {
  MediaService({
    required ApiClient apiClient,
    Dio? httpClient,
  })  : _client = apiClient,
        _http = httpClient ?? Dio();

final ApiClient _client;
final Dio _http;

  Future<PresignedMedia> fetchPresignedUrl({
    required String mediaId,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiPaths.mediaSign,
        body: {'media_id': mediaId},
      );

      final rawUrl =
          response['signed_url'] as String? ?? response['url'] as String?;
      if (rawUrl == null || rawUrl.isEmpty) {
        throw UnexpectedFailure(message: 'Signerad media-URL saknas.');
      }
      final url = _resolveSignedUrl(rawUrl);
      final expiresAtRaw = response['expires_at'] as String?;

      final expiresAt = expiresAtRaw != null
          ? DateTime.parse(expiresAtRaw).toUtc()
          : DateTime.now().toUtc();

      return PresignedMedia(
        url: url,
        headers: const {},
        expiresAt: expiresAt,
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<Uint8List> loadMedia(PresignedMedia presigned) async {
    try {
      final response = await _http.getUri<Object?>(
        presigned.url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: presigned.headers,
        ),
      );
      final data = response.data;
      if (data == null) {
        throw UnexpectedFailure(
          message: 'Tomt svar från media-endpoint.',
        );
      }
      if (data is Uint8List) {
        return data;
      }
      if (data is List<int>) {
        return Uint8List.fromList(data);
      }
      if (data is Iterable<int>) {
        return Uint8List.fromList(List<int>.from(data));
      }
      throw UnexpectedFailure(
        message: 'Kunde inte tolka mediat i svaret.',
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
  Future<PresignedUploadTarget> presignUpload({
    required String storagePath,
    required String contentType,
    bool upsert = false,
  }) async {
    if (storagePath.isEmpty || contentType.isEmpty) {
      throw UnexpectedFailure(
        message: 'Uppladdningen saknar sökväg eller content-type.',
      );
    }
    final mode = upsert ? 'upsert' : 'create';
    throw UnexpectedFailure(
      message:
          'Presign-uppladdning ($mode) stöds inte. Använd /api/upload-endpoints.',
    );
  }

  Future<void> uploadWithPresignedTarget({
    required PresignedUploadTarget target,
    required Uint8List bytes,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    try {
      if (target.method != 'PUT') {
        throw UnexpectedFailure(
          message: 'Presign returnerade ogiltig metod för uppladdning.',
        );
      }
      await _http.requestUri<void>(
        target.url,
        data: bytes,
        options: Options(
          method: target.method,
          headers: target.headers,
        ),
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<void> uploadViaPresignedUrl({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    bool upsert = false,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    final target = await presignUpload(
      storagePath: storagePath,
      contentType: contentType,
      upsert: upsert,
    );
    await uploadWithPresignedTarget(
      target: target,
      bytes: bytes,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
    );
  }

  Uri _resolveSignedUrl(String value) {
    final uri = Uri.parse(value);
    if (uri.hasScheme) {
      return uri;
    }
    final base = Uri.parse(_client.baseUrl);
    return base.resolve(value);
  }
}

final mediaServiceProvider = Provider<MediaService>((ref) {
  final client = ref.watch(apiClientProvider);
  return MediaService(apiClient: client);
});
