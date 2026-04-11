import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';

void main() {
  test('legacy media pipeline upload surface is inert before network', () async {
    final client = _clientWith(
      _RecordingAdapter((options) {
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      }),
    );
    final repo = MediaPipelineRepository(client: client);

    await expectLater(
      repo.requestUploadUrl(
        filename: 'demo.wav',
        mimeType: 'audio/wav',
        sizeBytes: 10,
        mediaType: 'audio',
        purpose: 'home_player_audio',
      ),
      throwsA(
        isA<CanonicalMediaSurfaceUnavailable>().having(
          (error) => error.toString(),
          'message',
          'Den har medieytan ar inte monterad i den kanoniska frontendmodellen.',
        ),
      ),
    );

    expect(client.raw.httpClientAdapter, isA<_RecordingAdapter>());
    final adapter = client.raw.httpClientAdapter as _RecordingAdapter;
    expect(adapter.requests, isEmpty);
  });

  test('lesson preview reads use canonical placement read shape', () async {
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
    final client = _clientWith(adapter);
    final repo = StudioRepository(client: client);

    final previews = await repo.fetchLessonMediaPreviews(['lesson-media-1']);

    expect(
      previews.itemFor('lesson-media-1')?.previewUrl,
      'https://cdn.example.com/preview.webp',
    );
    expect(adapter.requestsFor(placementReadPath), hasLength(1));
    expect(adapter.requestsFor(placementReadPath).single.method, 'GET');
  });
}

ApiClient _clientWith(_RecordingAdapter adapter) {
  final storage = _MemoryFlutterSecureStorage();
  final tokens = TokenStorage(storage: storage);
  final client = ApiClient(baseUrl: 'http://127.0.0.1:1', tokenStorage: tokens);
  client.raw.httpClientAdapter = adapter;
  return client;
}

ResponseBody _jsonResponse({
  required int statusCode,
  required Map<String, Object?> body,
}) {
  return ResponseBody.fromString(
    json.encode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._handler);

  final ResponseBody Function(RequestOptions options) _handler;
  final List<_RecordedRequest> _requests = <_RecordedRequest>[];

  List<_RecordedRequest> get requests => List.unmodifiable(_requests);

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
      ),
    );
    return _handler(options);
  }
}

class _RecordedRequest {
  const _RecordedRequest({required this.path, required this.method});

  final String path;
  final String method;
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
