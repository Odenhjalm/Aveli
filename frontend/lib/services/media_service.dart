import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_client.dart';
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
    required String storagePath,
    String? filename,
    int? ttlSeconds,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/media/presign',
        body: {
          'intent': 'download',
          'storage_path': storagePath,
          if (filename != null) 'filename': filename,
          if (ttlSeconds != null) 'ttl': ttlSeconds,
        },
      );

      final url = Uri.parse(response['url'] as String);
      final expiresAtRaw = response['expires_at'] as String?;
      final headers = _extractHeaders(response['headers']);

      final expiresAt = expiresAtRaw != null
          ? DateTime.parse(expiresAtRaw).toUtc()
          : DateTime.now().toUtc();

      return PresignedMedia(
        url: url,
        headers: headers,
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
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/media/presign',
        body: {
          'intent': 'upload',
          'storage_path': storagePath,
          'content_type': contentType,
          'upsert': upsert,
        },
      );
      final method =
          (response['method'] as String?)?.toUpperCase() ?? 'PUT';
      if (method != 'PUT') {
        throw UnexpectedFailure(
          message: 'Presign returnerade ogiltig metod för uppladdning.',
        );
      }
      final url = Uri.parse(response['url'] as String);
      final headers = _extractHeaders(response['headers']);
      final bucket = response['storage_bucket'] as String?;
      final path = response['storage_path'] as String?;
      return PresignedUploadTarget(
        url: url,
        headers: headers,
        method: method,
        storageBucket: bucket,
        storagePath: path,
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
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

  Map<String, String> _extractHeaders(dynamic raw) {
    if (raw is Map) {
      final result = <String, String>{};
      raw.forEach((key, value) {
        if (key is String && value is String) {
          result[key] = value;
        }
      });
      return result;
    }
    return const <String, String>{};
  }
}

final mediaServiceProvider = Provider<MediaService>((ref) {
  final client = ref.watch(apiClientProvider);
  return MediaService(apiClient: client);
});
