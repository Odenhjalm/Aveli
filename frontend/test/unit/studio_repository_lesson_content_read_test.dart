import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/features/studio/data/studio_models.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';

void main() {
  test(
    'LessonStudio rejects content authority fields in structure responses',
    () {
      expect(
        () => LessonStudio.fromResponse({
          'id': 'lesson-1',
          'course_id': 'course-1',
          'lesson_title': 'Lektion',
          'position': 1,
          'content_markdown': '# Persisted',
          'media': const [],
          'etag': '"content-v1"',
        }),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'readLessonContent uses dedicated content endpoint and preserves ETag',
    () async {
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/studio/lessons/lesson-1/content' &&
            options.method.toUpperCase() == 'GET') {
          return _jsonResponse(
            statusCode: 200,
            headers: {
              'etag': ['"content-v1"'],
            },
            body: {
              'lesson_id': 'lesson-1',
              'content_markdown': '# Persisted',
              'media': [
                {
                  'lesson_media_id': 'lesson-media-1',
                  'media_asset_id': 'media-1',
                  'position': 1,
                  'media_type': 'image',
                  'state': 'ready',
                },
              ],
            },
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = StudioRepository(client: _clientWith(adapter));

      final result = await repo.readLessonContent('lesson-1');

      expect(result.lessonId, 'lesson-1');
      expect(result.contentMarkdown, '# Persisted');
      expect(result.etag, '"content-v1"');
      expect(result.media.single.lessonMediaId, 'lesson-media-1');
      expect(result.media.single.mediaAssetId, 'media-1');
      expect(result.media.single.mediaType, 'image');

      final requests = adapter.requestsFor('/studio/lessons/lesson-1/content');
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
    },
  );

  test('updateLessonContent carries If-Match and replacement ETag', () async {
    final adapter = _RecordingAdapter((options) {
      if (options.path == '/studio/lessons/lesson-1/content' &&
          options.method.toUpperCase() == 'PATCH') {
        return _jsonResponse(
          statusCode: 200,
          headers: {
            'etag': ['"content-v2"'],
          },
          body: {'lesson_id': 'lesson-1', 'content_markdown': '# Updated'},
        );
      }
      return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
    });
    final repo = StudioRepository(client: _clientWith(adapter));

    final result = await repo.updateLessonContent(
      'lesson-1',
      contentMarkdown: '# Updated',
      ifMatch: ' "content-v1" ',
    );

    expect(result.lessonId, 'lesson-1');
    expect(result.contentMarkdown, '# Updated');
    expect(result.etag, '"content-v2"');

    final requests = adapter.requestsFor('/studio/lessons/lesson-1/content');
    expect(requests, hasLength(1));
    expect(requests.single.method, 'PATCH');
    expect(requests.single.headers['If-Match'], '"content-v1"');
    expect(Map<String, dynamic>.from(requests.single.data as Map), {
      'content_markdown': '# Updated',
    });
  });

  test(
    'updateLessonContent rejects tokenless writes before transport',
    () async {
      final adapter = _RecordingAdapter(
        (_) => _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'}),
      );
      final repo = StudioRepository(client: _clientWith(adapter));

      await expectLater(
        repo.updateLessonContent(
          'lesson-1',
          contentMarkdown: '# Updated',
          ifMatch: ' ',
        ),
        throwsA(isA<StateError>()),
      );
      expect(adapter.requestsFor('/studio/lessons/lesson-1/content'), isEmpty);
    },
  );
}

ApiClient _clientWith(_RecordingAdapter adapter) {
  final client = ApiClient(
    baseUrl: 'http://127.0.0.1:1',
    tokenStorage: _FakeTokenStorage(),
  );
  client.raw.httpClientAdapter = adapter;
  return client;
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
    required this.headers,
    required this.data,
  });

  final String path;
  final String method;
  final Map<String, Object?> headers;
  final Object? data;
}

class _FakeTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readAccessToken() async => _jwtWithExpSeconds(4102444800);

  @override
  Future<String?> readRefreshToken() async => 'rt-1';

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> updateAccessToken(String accessToken) async {}
}

String _jwtWithExpSeconds(int expSeconds) {
  final header = base64Url.encode(utf8.encode(json.encode({'alg': 'HS256'})));
  final payload = base64Url.encode(
    utf8.encode(json.encode({'exp': expSeconds})),
  );
  return '$header.$payload.signature';
}
