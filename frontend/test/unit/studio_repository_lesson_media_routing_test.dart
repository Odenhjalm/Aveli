import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';

void main() {
  test(
    'listLessonMedia reconstructs from lesson content and canonical placements',
    () async {
      final harness = await _Harness.create();
      final repo = StudioRepository(client: harness.client);

      final items = await repo.listLessonMedia('lesson-1');

      expect(items.map((item) => item.lessonMediaId), [
        'lesson-media-1',
        'lesson-media-2',
      ]);
      expect(items.first.position, 1);
      expect(items.first.mediaType, 'document');
      expect(items.first.originalName, isNull);
      expect(items.first.media?.mediaId, 'media-1');
      expect(items.first.media?.state, 'ready');
      expect(
        items.first.media?.resolvedUrl,
        'https://cdn.example.test/guide.pdf',
      );
      expect(items.last.position, 2);
      expect(items.last.mediaType, 'video');
      expect(items.last.state, 'processing');
      expect(items.last.media, isNull);

      final contentRequests = harness.adapter.requestsFor(
        '/studio/lessons/lesson-1/content',
      );
      expect(contentRequests, hasLength(1));
      expect(contentRequests.single.method, 'GET');
      expect(
        harness.adapter.requestsFor('/api/media-placements/lesson-media-1'),
        hasLength(1),
      );
      expect(
        harness.adapter.requestsFor('/api/media-placements/lesson-media-2'),
        hasLength(1),
      );
      expect(
        harness.adapter.requestsFor('/api/lesson-media/lesson-1'),
        isEmpty,
      );
    },
  );

  test('uploadLessonMedia uses canonical studio upload endpoints', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    final uploaded = await repo.uploadLessonMedia(
      lessonId: 'lesson-1',
      data: Uint8List.fromList(List<int>.generate(16, (index) => index)),
      filename: 'guide.pdf',
      contentType: 'application/pdf',
      mediaType: 'document',
    );

    expect(uploaded.lessonMediaId, 'lesson-media-1');
    expect(uploaded.mediaType, 'document');
    expect(uploaded.media?.mediaId, 'media-1');
    expect(
      uploaded.media?.resolvedUrl,
      'https://cdn.example.test/guide.pdf?token=studio',
    );

    final uploadTargetRequests = harness.adapter.requestsFor(
      '/api/lessons/lesson-1/media-assets/upload-url',
    );
    final completeRequests = harness.adapter.requestsFor(
      '/api/media-assets/media-1/upload-completion',
    );
    final placementRequests = harness.adapter.requestsFor(
      '/api/lessons/lesson-1/media-placements',
    );

    expect(uploadTargetRequests, hasLength(1));
    expect(completeRequests, hasLength(1));
    expect(placementRequests, hasLength(1));
    final byteUploadRequests = harness.adapter.requestsFor(
      '/api/media-assets/media-1/upload-bytes',
    );
    expect(byteUploadRequests, hasLength(1));
    expect(byteUploadRequests.single.method, 'PUT');
    expect(byteUploadRequests.single.contentType, 'application/pdf');
    expect(
      byteUploadRequests.single.headers['X-Aveli-Upload-Session'],
      'upload-session-1',
    );
    expect(harness.adapter.recordedPathContaining('/direct/'), isFalse);

    final uploadPayload = Map<String, dynamic>.from(
      uploadTargetRequests.single.data as Map,
    );
    expect(uploadPayload, {
      'filename': 'guide.pdf',
      'mime_type': 'application/pdf',
      'size_bytes': 16,
      'media_type': 'document',
    });

    expect(
      Map<String, dynamic>.from(completeRequests.single.data as Map),
      <String, dynamic>{},
    );
    expect(Map<String, dynamic>.from(placementRequests.single.data as Map), {
      'media_asset_id': 'media-1',
    });
  });

  test('fetchLessonMediaPreviews uses canonical placement reads', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    final previews = await repo.fetchLessonMediaPreviews(['lesson-media-1']);
    final preview = previews.itemFor('lesson-media-1');

    expect(preview, isNotNull);
    expect(preview?.previewUrl, 'https://cdn.example.test/guide.pdf');

    final requests = harness.adapter.requestsFor(
      '/api/media-placements/lesson-media-1',
    );
    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
  });

  test('deleteLessonMedia uses canonical placement delete', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    await repo.deleteLessonMedia('lesson-1', 'lesson-media-1');

    final requests = harness.adapter.requestsFor(
      '/api/media-placements/lesson-media-1',
    );
    expect(requests, hasLength(1));
    expect(requests.single.method, 'DELETE');
    expect(
      harness.adapter.requestsFor('/api/lesson-media/lesson-1/lesson-media-1'),
      isEmpty,
    );
  });

  test('reorderLessonMedia uses canonical placement reorder', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    await repo.reorderLessonMedia('lesson-1', [
      'lesson-media-2',
      'lesson-media-1',
    ]);

    final requests = harness.adapter.requestsFor(
      '/api/lessons/lesson-1/media-placements/reorder',
    );
    expect(requests, hasLength(1));
    expect(requests.single.method, 'PATCH');
    expect(Map<String, dynamic>.from(requests.single.data as Map), {
      'lesson_media_ids': ['lesson-media-2', 'lesson-media-1'],
    });
    expect(
      harness.adapter.requestsFor('/api/lesson-media/lesson-1/reorder'),
      isEmpty,
    );
  });
}

class _Harness {
  _Harness({required this.client, required this.adapter});

  final ApiClient client;
  final _RecordingAdapter adapter;

  static Future<_Harness> create() async {
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
      if (options.path == '/studio/lessons/lesson-1/content') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'lesson_id': 'lesson-1',
            'content_document': {
              'schema_version': 'lesson_document_v1',
              'blocks': <Object?>[],
            },
            'media': [
              {
                'lesson_media_id': 'lesson-media-2',
                'media_asset_id': 'media-2',
                'position': 2,
                'media_type': 'video',
                'state': 'processing',
              },
              {
                'lesson_media_id': 'lesson-media-1',
                'media_asset_id': 'media-1',
                'position': 1,
                'media_type': 'document',
                'state': 'ready',
              },
            ],
          },
          headers: {
            'etag': ['"content-v1"'],
          },
        );
      }
      if (options.path == '/api/lessons/lesson-1/media-assets/upload-url') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'media_asset_id': 'media-1',
            'asset_state': 'pending_upload',
            'upload_session_id': 'upload-session-1',
            'upload_endpoint': '/api/media-assets/media-1/upload-bytes',
            'expires_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
      }
      if (options.path == '/api/media-assets/media-1/upload-bytes') {
        return _jsonResponse(statusCode: 200, body: {'uploaded': true});
      }
      if (options.path == '/api/media-assets/media-1/upload-completion') {
        return _jsonResponse(
          statusCode: 200,
          body: {'media_asset_id': 'media-1', 'asset_state': 'uploaded'},
        );
      }
      if (options.path == '/api/lessons/lesson-1/media-placements') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'lesson_media_id': 'lesson-media-1',
            'lesson_id': 'lesson-1',
            'media_asset_id': 'media-1',
            'position': 1,
            'media_type': 'document',
            'asset_state': 'ready',
            'media': {
              'media_id': 'media-1',
              'state': 'ready',
              'resolved_url': 'https://cdn.example.test/guide.pdf?token=studio',
            },
          },
        );
      }
      if (options.path == '/api/media-placements/lesson-media-1') {
        if (options.method.toUpperCase() == 'DELETE') {
          return _jsonResponse(statusCode: 200, body: {'deleted': true});
        }
        return _jsonResponse(
          statusCode: 200,
          body: {
            'lesson_media_id': 'lesson-media-1',
            'lesson_id': 'lesson-1',
            'media_asset_id': 'media-1',
            'position': 1,
            'media_type': 'document',
            'asset_state': 'ready',
            'media': {
              'media_id': 'media-1',
              'state': 'ready',
              'resolved_url': 'https://cdn.example.test/guide.pdf',
            },
          },
        );
      }
      if (options.path == '/api/media-placements/lesson-media-2') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'lesson_media_id': 'lesson-media-2',
            'lesson_id': 'lesson-1',
            'media_asset_id': 'media-2',
            'position': 2,
            'media_type': 'video',
            'asset_state': 'processing',
            'media': null,
          },
        );
      }
      if (options.path == '/api/lessons/lesson-1/media-placements/reorder') {
        return _jsonResponse(statusCode: 200, body: {'ok': true});
      }
      return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
    });
    client.raw.httpClientAdapter = adapter;
    return _Harness(client: client, adapter: adapter);
  }
}

ResponseBody _jsonResponse({
  required int statusCode,
  required Map<String, dynamic> body,
  Map<String, List<String>> headers = const <String, List<String>>{},
}) {
  return ResponseBody.fromString(
    json.encode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
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

  bool recordedPathContaining(String value) {
    return _requests.any((request) => request.path.contains(value));
  }

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
        headers: Map<String, Object?>.from(options.headers),
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
  final Map<String, Object?> headers;
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
