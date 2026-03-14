import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';

void main() {
  late _UploadServer uploadServer;

  setUp(() async {
    uploadServer = await _UploadServer.start();
  });

  tearDown(() async {
    await uploadServer.close();
  });

  test('lesson MP3/WAV/M4A uploads use the audio pipeline', () async {
    final harness = await _Harness.create(uploadServer: uploadServer);
    final repo = StudioRepository(client: harness.client);

    Future<void> expectAudioPipeline({
      required String filename,
      required String mimeType,
      required String expectedObjectPath,
    }) async {
      harness.adapter.clear();
      uploadServer.putPaths.clear();

      await repo.uploadLessonMedia(
        courseId: 'course-1',
        lessonId: 'lesson-1',
        data: Uint8List.fromList(List<int>.generate(16, (index) => index)),
        filename: filename,
        contentType: mimeType,
        isIntro: false,
      );

      final uploadUrlRequests = harness.adapter.requestsFor(
        ApiPaths.mediaUploadUrl,
      );
      final completeRequests = harness.adapter.requestsFor(
        ApiPaths.mediaUploadUrlComplete,
      );
      expect(uploadUrlRequests, hasLength(1));
      expect(completeRequests, hasLength(1));
      expect(harness.adapter.requestsFor('/api/upload/course-media'), isEmpty);
      expect(
        harness.adapter.requestsFor('/studio/lessons/lesson-1/media/presign'),
        isEmpty,
      );

      final uploadPayload = Map<String, dynamic>.from(
        uploadUrlRequests.single.data as Map,
      );
      expect(uploadPayload['media_type'], 'audio');
      expect(uploadPayload['lesson_id'], 'lesson-1');
      expect(uploadPayload['course_id'], 'course-1');
      expect(uploadPayload['filename'], filename);
      expect(uploadPayload['mime_type'], mimeType);

      final completePayload = Map<String, dynamic>.from(
        completeRequests.single.data as Map,
      );
      expect(completePayload['media_id'], 'media-1');

      expect(uploadServer.putPaths, contains(expectedObjectPath));
    }

    await expectAudioPipeline(
      filename: 'lesson.mp3',
      mimeType: 'audio/mpeg',
      expectedObjectPath: '/audio/lesson.mp3',
    );
    await expectAudioPipeline(
      filename: 'lesson.wav',
      mimeType: 'audio/wav',
      expectedObjectPath: '/audio/lesson.wav',
    );
    await expectAudioPipeline(
      filename: 'lesson.m4a',
      mimeType: 'audio/mp4',
      expectedObjectPath: '/audio/lesson.m4a',
    );
  });

  test(
    'lesson PDF/video keep direct pipeline and image keeps legacy route',
    () async {
      final harness = await _Harness.create(uploadServer: uploadServer);
      final repo = StudioRepository(client: harness.client);

      harness.adapter.clear();
      await repo.uploadLessonMedia(
        courseId: 'course-1',
        lessonId: 'lesson-1',
        data: Uint8List.fromList(List<int>.filled(8, 7)),
        filename: 'guide.pdf',
        contentType: 'application/pdf',
        isIntro: false,
      );
      expect(
        harness.adapter.requestsFor('/studio/lessons/lesson-1/media/presign'),
        hasLength(1),
      );
      expect(
        harness.adapter.requestsFor('/studio/lessons/lesson-1/media/complete'),
        hasLength(1),
      );
      expect(harness.adapter.requestsFor(ApiPaths.mediaUploadUrl), isEmpty);
      expect(harness.adapter.requestsFor('/api/upload/course-media'), isEmpty);

      harness.adapter.clear();
      await repo.uploadLessonMedia(
        courseId: 'course-1',
        lessonId: 'lesson-1',
        data: Uint8List.fromList(List<int>.filled(8, 9)),
        filename: 'lesson.mp4',
        contentType: 'video/mp4',
        isIntro: false,
      );
      expect(
        harness.adapter.requestsFor('/studio/lessons/lesson-1/media/presign'),
        hasLength(1),
      );
      expect(
        harness.adapter.requestsFor('/studio/lessons/lesson-1/media/complete'),
        hasLength(1),
      );
      expect(harness.adapter.requestsFor(ApiPaths.mediaUploadUrl), isEmpty);
      expect(harness.adapter.requestsFor('/api/upload/course-media'), isEmpty);

      harness.adapter.clear();
      await repo.uploadLessonMedia(
        courseId: 'course-1',
        lessonId: 'lesson-1',
        data: Uint8List.fromList(List<int>.filled(8, 3)),
        filename: 'diagram.png',
        contentType: 'image/png',
        isIntro: false,
      );
      expect(
        harness.adapter.requestsFor('/api/upload/course-media'),
        hasLength(1),
      );
      expect(
        harness.adapter.requestsFor('/studio/lessons/lesson-1/media/presign'),
        isEmpty,
      );
      expect(harness.adapter.requestsFor(ApiPaths.mediaUploadUrl), isEmpty);
    },
  );
}

class _Harness {
  _Harness({required this.client, required this.adapter});

  final ApiClient client;
  final _RecordingAdapter adapter;

  static Future<_Harness> create({required _UploadServer uploadServer}) async {
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
        final payload = Map<String, dynamic>.from(options.data as Map);
        final filename = payload['filename'] as String;
        return _jsonResponse(
          statusCode: 200,
          body: {
            'media_asset_id': 'media-1',
            'upload_url': uploadServer.url('/audio/$filename').toString(),
            'storage_path':
                'media/source/audio/courses/course-1/lessons/lesson-1/$filename',
            'headers': const <String, String>{},
            'expires_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
      }
      if (options.path == ApiPaths.mediaUploadUrlComplete) {
        return _jsonResponse(
          statusCode: 200,
          body: {'media_id': 'media-1', 'state': 'uploaded'},
        );
      }
      if (options.path == '/studio/lessons/lesson-1/media/presign') {
        final payload = Map<String, dynamic>.from(options.data as Map);
        final filename = payload['filename'] as String;
        return _jsonResponse(
          statusCode: 200,
          body: {
            'url': uploadServer.url('/direct/$filename').toString(),
            'storage_path': 'lessons/lesson-1/$filename',
            'storage_bucket': 'course-media',
            'headers': const <String, String>{},
            'method': 'PUT',
          },
        );
      }
      if (options.path == '/studio/lessons/lesson-1/media/complete') {
        final payload = Map<String, dynamic>.from(options.data as Map);
        return _jsonResponse(
          statusCode: 200,
          body: {
            'id': 'lesson-media-1',
            'kind': payload['content_type'] == 'application/pdf'
                ? 'pdf'
                : 'video',
            'storage_path': payload['storage_path'],
            'storage_bucket': payload['storage_bucket'],
            'content_type': payload['content_type'],
            'original_name': payload['original_name'],
          },
        );
      }
      if (options.path == '/api/upload/course-media') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'media': {
              'id': 'lesson-media-legacy-1',
              'kind': 'image',
              'storage_path': 'courses/course-1/diagram.png',
              'storage_bucket': 'course-media',
            },
          },
        );
      }
      return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
    });
    client.raw.httpClientAdapter = adapter;
    return _Harness(client: client, adapter: adapter);
  }
}

class _UploadServer {
  _UploadServer(this._server) {
    _subscription = _server.listen(_handle);
  }

  final HttpServer _server;
  late final StreamSubscription<HttpRequest> _subscription;
  final List<String> putPaths = <String>[];

  static Future<_UploadServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _UploadServer(server);
  }

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_server.port}$path');

  Future<void> _handle(HttpRequest request) async {
    if (request.method.toUpperCase() == 'PUT') {
      putPaths.add(request.uri.path);
    }
    await request.drain<void>();
    request.response.statusCode = HttpStatus.ok;
    await request.response.close();
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }
}

ResponseBody _jsonResponse({
  required int statusCode,
  required Map<String, dynamic> body,
}) {
  return ResponseBody.fromString(
    json.encode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
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

  void clear() => _requests.clear();

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
    required this.data,
  });

  final String path;
  final String method;
  final String contentType;
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
