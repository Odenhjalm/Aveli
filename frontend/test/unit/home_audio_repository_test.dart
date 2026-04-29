import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/features/home/data/home_audio_repository.dart';

void main() {
  test(
    'fetchHomeAudio parses canonical runtime items and backend text bundle',
    () async {
      final harness = await _Harness.create();
      final repo = HomeAudioRepository(harness.client);

      final payload = await repo.fetchHomeAudio(limit: 8);

      expect(payload.items, hasLength(2));
      expect(payload.items.first.sourceType, HomeAudioSourceType.directUpload);
      expect(payload.items.first.title, 'Kvällsmeditation');
      expect(payload.items.first.media.mediaId, 'media-1');
      expect(payload.items.first.media.state, 'ready');
      expect(
        payload.items.first.media.resolvedUrl,
        'https://cdn.test/audio/evening.mp3',
      );
      expect(payload.items.last.sourceType, HomeAudioSourceType.courseLink);
      expect(payload.items.last.lessonTitle, 'Lektion 1');
      expect(payload.items.last.courseTitle, 'Andning');
      expect(payload.items.last.media.resolvedUrl, isNull);
      expect(
        payload.homeplayerLogo.closed.resolvedUrl,
        'https://storage.test/storage/v1/object/public/public-media/home-player/logos/v1/homeplayer_logo_closed.png',
      );
      expect(payload.homeplayerLogo.open.assetKey, 'homeplayer_logo_open');
      expect(
        payload.textBundle.requireValue('home.audio.section_title'),
        'Ljud i Home-spelaren',
      );

      final requests = harness.adapter.requestsFor('/home/audio');
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
    },
  );

  test('fetchHomeAudio rejects forbidden runtime fields', () async {
    final harness = await _Harness.create(
      handler: (options) => _jsonResponse(
        statusCode: 200,
        body: {
          'items': [
            {
              'source_type': 'direct_upload',
              'title': 'Invalid',
              'teacher_id': 'teacher-1',
              'created_at': '2026-04-21T10:00:00Z',
              'runtime_media_id': 'runtime-1',
              'media': {
                'media_id': 'media-1',
                'state': 'ready',
                'resolved_url': 'https://cdn.test/audio/invalid.mp3',
              },
            },
          ],
          'homeplayer_logo': _homeplayerLogoPayload(),
          'text_bundle': const {},
        },
      ),
    );
    final repo = HomeAudioRepository(harness.client);

    expect(repo.fetchHomeAudio(), throwsStateError);
  });
}

class _Harness {
  _Harness({required this.client, required this.adapter});

  final ApiClient client;
  final _RecordingAdapter adapter;

  static Future<_Harness> create({
    ResponseBody Function(RequestOptions options)? handler,
  }) async {
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
    final adapter = _RecordingAdapter(handler ?? _defaultHandler);
    client.raw.httpClientAdapter = adapter;
    return _Harness(client: client, adapter: adapter);
  }
}

ResponseBody _defaultHandler(RequestOptions options) {
  if (options.path == '/home/audio' && options.method.toUpperCase() == 'GET') {
    return _jsonResponse(
      statusCode: 200,
      body: {
        'items': [
          {
            'source_type': 'direct_upload',
            'title': 'Kvällsmeditation',
            'lesson_title': null,
            'course_id': null,
            'course_title': null,
            'course_slug': null,
            'teacher_id': 'teacher-1',
            'teacher_name': 'Aveli Teacher',
            'created_at': '2026-04-21T10:00:00Z',
            'media': {
              'media_id': 'media-1',
              'state': 'ready',
              'resolved_url': 'https://cdn.test/audio/evening.mp3',
            },
          },
          {
            'source_type': 'course_link',
            'title': 'Andning del 1',
            'lesson_title': 'Lektion 1',
            'course_id': 'course-1',
            'course_title': 'Andning',
            'course_slug': 'andning',
            'teacher_id': 'teacher-2',
            'teacher_name': 'Aveli Course Teacher',
            'created_at': '2026-04-21T09:00:00Z',
            'media': {
              'media_id': 'media-2',
              'state': 'processing',
              'resolved_url': null,
            },
          },
        ],
        'homeplayer_logo': _homeplayerLogoPayload(),
        'text_bundle': {
          'home.audio.section_title': {
            'surface_id': 'TXT-SURF-076',
            'text_id': 'home.audio.section_title',
            'authority_class': 'contract_text',
            'canonical_owner': 'backend_text_catalog',
            'source_contract':
                'actual_truth/contracts/backend_text_catalog_contract.md',
            'backend_namespace': 'backend_text_catalog.home',
            'api_surface': '/home/audio',
            'delivery_surface': '/home/audio',
            'render_surface':
                'frontend/lib/features/home/presentation/widgets/home_audio_section.dart',
            'language': 'sv',
            'interpolation_keys': const [],
            'forbidden_render_fields': const [],
            'value': 'Ljud i Home-spelaren',
          },
        },
      },
    );
  }
  return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
}

Map<String, Object?> _homeplayerLogoPayload() {
  return const {
    'closed': {
      'asset_key': 'homeplayer_logo_closed',
      'resolved_url':
          'https://storage.test/storage/v1/object/public/public-media/home-player/logos/v1/homeplayer_logo_closed.png',
    },
    'open': {
      'asset_key': 'homeplayer_logo_open',
      'resolved_url':
          'https://storage.test/storage/v1/object/public/public-media/home-player/logos/v1/homeplayer_logo_open.png',
    },
  };
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
    required this.data,
  });

  final String path;
  final String method;
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
}
