import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';

void main() {
  test(
    'lesson media upload-url callers are rejected before /api/media/upload-url',
    () async {
      final storage = _MemoryFlutterSecureStorage();
      final tokens = TokenStorage(storage: storage);
      await tokens.saveTokens(
        accessToken: _jwtWithExpSeconds(4102444800),
        refreshToken: 'rt-1',
      );

      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:1',
        tokenStorage: tokens,
      );

      final adapter = _RecordingAdapter((options) {
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      client.raw.httpClientAdapter = adapter;

      final repo = MediaPipelineRepository(client: client);

      await expectLater(
        repo.requestUploadUrl(
          filename: 'demo.wav',
          mimeType: 'audio/wav',
          sizeBytes: 10,
          mediaType: 'audio',
          courseId: '00000000-0000-0000-0000-000000000001',
          lessonId: '00000000-0000-0000-0000-000000000002',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            'Lesson media uploads use StudioRepository.uploadLessonMedia.',
          ),
        ),
      );

      expect(adapter.requestsFor(ApiPaths.mediaUploadUrl), isEmpty);
    },
  );

  test(
    'lesson-audio upload contract points callers to canonical studio media',
    () async {
      final storage = _MemoryFlutterSecureStorage();
      final tokens = TokenStorage(storage: storage);
      await tokens.saveTokens(
        accessToken: _jwtWithExpSeconds(4102444800),
        refreshToken: 'rt-1',
      );

      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:1',
        tokenStorage: tokens,
      );
      final repo = MediaPipelineRepository(client: client);

      await expectLater(
        repo.requestUploadUrl(
          filename: 'demo.wav',
          mimeType: 'audio/wav',
          sizeBytes: 10,
          mediaType: 'audio',
          courseId: '00000000-0000-0000-0000-000000000001',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            'Lesson media uploads use StudioRepository.uploadLessonMedia.',
          ),
        ),
      );
    },
  );

  test('upload-url contract guard rejects multipart/FormData', () async {
    final storage = _MemoryFlutterSecureStorage();
    final tokens = TokenStorage(storage: storage);
    await tokens.saveTokens(
      accessToken: _jwtWithExpSeconds(4102444800),
      refreshToken: 'rt-1',
    );

    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:1',
      tokenStorage: tokens,
    );
    final adapter = _RecordingAdapter(
      (options) =>
          _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'}),
    );
    client.raw.httpClientAdapter = adapter;

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        filename: 'demo.wav',
      ),
    });

    await expectLater(
      () => client.postForm<Map<String, dynamic>>(
        ApiPaths.mediaUploadUrl,
        formData,
      ),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'statusCode',
          400,
        ),
      ),
    );
    expect(adapter.requestsFor(ApiPaths.mediaUploadUrl), isEmpty);
  });

  test('lesson preview reads use canonical placement read shape', () async {
    final storage = _MemoryFlutterSecureStorage();
    final tokens = TokenStorage(storage: storage);
    await tokens.saveTokens(
      accessToken: _jwtWithExpSeconds(4102444800),
      refreshToken: 'rt-1',
    );

    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:1',
      tokenStorage: tokens,
    );
    const placementReadPath = '/api/media-placements/lesson-media-1';
    final adapter = _RecordingAdapter((options) {
      if (options.path == placementReadPath) {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'lesson_media_id': 'lesson-media-1',
            'lesson_id': 'lesson-1',
            'media_asset_id': 'media-1',
            'position': 1,
            'media_type': 'image',
            'asset_state': 'ready',
            'media': {
              'media_id': 'media-1',
              'state': 'ready',
              'resolved_url': 'https://cdn.example.com/preview.webp',
            },
          },
        );
      }
      return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
    });
    client.raw.httpClientAdapter = adapter;
    final repo = StudioRepository(client: client);

    final previews = await repo.fetchLessonMediaPreviews(['lesson-media-1']);

    expect(
      previews.itemFor('lesson-media-1')?.previewUrl,
      'https://cdn.example.com/preview.webp',
    );

    final requests = adapter.requestsFor(placementReadPath);
    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
    expect(adapter.requestsFor(ApiPaths.mediaPreviews), isEmpty);
  });
}

ResponseBody _jsonResponse({
  required int statusCode,
  required Map<String, dynamic> body,
}) {
  return ResponseBody.fromString(
    json.encode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

String _jwtWithExpSeconds(int expSeconds) {
  final header = base64Url.encode(utf8.encode(json.encode({'alg': 'HS256'})));
  final payload = base64Url.encode(
    utf8.encode(json.encode({'exp': expSeconds})),
  );
  return '$header.$payload.signature';
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._handler);

  final ResponseBody Function(RequestOptions options) _handler;
  final List<_RecordedRequest> _requests = <_RecordedRequest>[];

  List<_RecordedRequest> requestsFor(String path) => _requests
      .where((request) => request.path == path)
      .toList(growable: false);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _requests.add(
      _RecordedRequest(
        path: options.path,
        method: options.method.toUpperCase(),
        contentType:
            (options.contentType ??
                    options.headers[Headers.contentTypeHeader]?.toString() ??
                    '')
                .toString(),
        headers: Map<String, dynamic>.from(options.headers),
        data: options.data,
      ),
    );
    return _handler(options);
  }
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.path,
    required this.method,
    required this.contentType,
    required this.headers,
    required this.data,
  });

  final String path;
  final String method;
  final String contentType;
  final Map<String, dynamic> headers;
  final Object? data;
}

class _MemoryFlutterSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    _values.clear();
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    return Map<String, String>.from(_values);
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    return _values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    return _values.containsKey(key);
  }
}
