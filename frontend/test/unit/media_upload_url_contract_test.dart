import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';

void main() {
  test(
    'upload-url requests use POST + JSON and match expected payloads',
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
        if (options.path == ApiPaths.mediaUploadUrl) {
          return _jsonResponse(
            statusCode: 200,
            body: {
              'media_id': 'media-1',
              'upload_url': 'https://storage.test/upload',
              'object_path': 'media/source/audio/demo.wav',
              'headers': const <String, String>{},
              'expires_at': DateTime.now().toUtc().toIso8601String(),
            },
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      client.raw.httpClientAdapter = adapter;

      final repo = MediaPipelineRepository(client: client);

      await repo.requestUploadUrl(
        filename: 'demo.wav',
        mimeType: 'audio/wav',
        sizeBytes: 10,
        mediaType: 'audio',
        courseId: '00000000-0000-0000-0000-000000000001',
        lessonId: '00000000-0000-0000-0000-000000000002',
      );

      await repo.requestUploadUrl(
        filename: 'demo.wav',
        mimeType: 'audio/wav',
        sizeBytes: 10,
        mediaType: 'audio',
        purpose: 'home_player_audio',
      );

      final requests = adapter.requestsFor(ApiPaths.mediaUploadUrl);
      expect(requests.length, 2);

      final lessonRequest = requests.first;
      final homePlayerRequest = requests.last;

      expect(lessonRequest.method, 'POST');
      expect(homePlayerRequest.method, 'POST');
      expect(
        lessonRequest.contentType.toLowerCase().startsWith('application/json'),
        true,
      );
      expect(
        homePlayerRequest.contentType.toLowerCase().startsWith(
          'application/json',
        ),
        true,
      );

      final lessonPayload = Map<String, dynamic>.from(
        lessonRequest.data as Map,
      );
      final homePayload = Map<String, dynamic>.from(
        homePlayerRequest.data as Map,
      );

      expect(lessonPayload.keys.toSet(), {
        'filename',
        'mime_type',
        'size_bytes',
        'media_type',
        'course_id',
        'lesson_id',
      });
      expect(lessonPayload['media_type'], 'audio');
      expect(lessonPayload['course_id'], isNotNull);
      expect(lessonPayload['lesson_id'], isNotNull);
      expect(lessonPayload.containsKey('purpose'), false);

      expect(homePayload.keys.toSet(), {
        'filename',
        'mime_type',
        'size_bytes',
        'media_type',
        'purpose',
      });
      expect(homePayload['media_type'], 'audio');
      expect(homePayload['purpose'], 'home_player_audio');
      expect(homePayload.containsKey('course_id'), false);
      expect(homePayload.containsKey('lesson_id'), false);
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
  _MemoryFlutterSecureStorage();

  final Map<String, String?> _storage = <String, String?>{};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _storage[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _storage[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _storage.remove(key);
  }
}
