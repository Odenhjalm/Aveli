import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/media/data/profile_avatar_repository.dart';

void main() {
  test(
    'profile avatar upload uses canonical backend-mediated endpoints',
    () async {
      final harness = await _Harness.create();
      final repo = ProfileAvatarRepository(
        client: harness.client,
        mediaPipeline: MediaPipelineRepository(client: harness.client),
      );

      final target = await repo.initUpload(
        filename: 'avatar.png',
        mimeType: 'image/png',
        sizeBytes: 4,
      );
      await repo.uploadBytes(
        target: target,
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        contentType: 'image/png',
      );
      final completion = await repo.completeUpload(
        mediaAssetId: target.mediaId,
      );
      final status = await repo.fetchStatus(mediaAssetId: target.mediaId);
      final profile = await repo.attachAvatar(mediaAssetId: target.mediaId);

      expect(target.mediaId, 'media-1');
      expect(target.uploadEndpoint, ApiPaths.mediaAssetUploadBytes('media-1'));
      expect(completion.state, 'uploaded');
      expect(status.state, 'ready');
      expect(profile.avatarMediaId, 'media-1');

      final initRequests = harness.adapter.requestsFor(
        ApiPaths.profileAvatarInit,
      );
      final uploadRequests = harness.adapter.requestsFor(
        ApiPaths.mediaAssetUploadBytes('media-1'),
      );
      final completionRequests = harness.adapter.requestsFor(
        ApiPaths.mediaAssetUploadCompletion('media-1'),
      );
      final statusRequests = harness.adapter.requestsFor(
        ApiPaths.mediaAssetStatus('media-1'),
      );
      final attachRequests = harness.adapter.requestsFor(
        ApiPaths.profileAvatarAttach,
      );

      expect(initRequests, hasLength(1));
      expect(uploadRequests, hasLength(1));
      expect(completionRequests, hasLength(1));
      expect(statusRequests, hasLength(1));
      expect(attachRequests, hasLength(1));
      expect(initRequests.single.method, 'POST');
      expect(Map<String, dynamic>.from(initRequests.single.data as Map), {
        'filename': 'avatar.png',
        'mime_type': 'image/png',
        'size_bytes': 4,
      });
      expect(uploadRequests.single.method, 'PUT');
      expect(uploadRequests.single.contentType, startsWith('image/png'));
      expect(
        uploadRequests.single.headers['X-Aveli-Upload-Session'],
        'media-1',
      );
      expect(uploadRequests.single.data, isA<Uint8List>());
      expect(completionRequests.single.method, 'POST');
      expect(attachRequests.single.method, 'POST');
      expect(Map<String, dynamic>.from(attachRequests.single.data as Map), {
        'media_asset_id': 'media-1',
      });
    },
  );

  test('profile avatar init rejects non-canonical upload endpoints', () async {
    final harness = await _Harness.create(
      uploadEndpoint: 'https://storage.example.test/avatar.png',
    );
    final repo = ProfileAvatarRepository(
      client: harness.client,
      mediaPipeline: MediaPipelineRepository(client: harness.client),
    );

    expect(
      () => repo.initUpload(
        filename: 'avatar.png',
        mimeType: 'image/png',
        sizeBytes: 4,
      ),
      throwsA(isA<StateError>()),
    );
  });
}

class _Harness {
  _Harness({required this.client, required this.adapter});

  final ApiClient client;
  final _RecordingAdapter adapter;

  static Future<_Harness> create({String? uploadEndpoint}) async {
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
      final path = options.path;
      if (path == ApiPaths.profileAvatarInit) {
        return _jsonResponse(
          statusCode: 200,
          body: <String, dynamic>{
            'media_asset_id': 'media-1',
            'asset_state': 'pending_upload',
            'upload_session_id': 'media-1',
            'upload_endpoint':
                uploadEndpoint ?? ApiPaths.mediaAssetUploadBytes('media-1'),
            'expires_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
      }
      if (path == ApiPaths.mediaAssetUploadBytes('media-1')) {
        return _jsonResponse(
          statusCode: 200,
          body: <String, dynamic>{
            'media_asset_id': 'media-1',
            'uploaded': true,
          },
        );
      }
      if (path == ApiPaths.mediaAssetUploadCompletion('media-1')) {
        return _jsonResponse(
          statusCode: 200,
          body: <String, dynamic>{
            'media_asset_id': 'media-1',
            'asset_state': 'uploaded',
          },
        );
      }
      if (path == ApiPaths.mediaAssetStatus('media-1')) {
        return _jsonResponse(
          statusCode: 200,
          body: <String, dynamic>{
            'media_asset_id': 'media-1',
            'asset_state': 'ready',
          },
        );
      }
      if (path == ApiPaths.profileAvatarAttach) {
        return _jsonResponse(
          statusCode: 200,
          body: <String, dynamic>{
            'user_id': 'user-1',
            'email': 'user@example.com',
            'display_name': 'Aveli User',
            'bio': '',
            'photo_url': '/api/runtime-media/avatar/media-1',
            'avatar_media_id': 'media-1',
            'created_at': '2024-01-01T00:00:00Z',
            'updated_at': '2024-01-01T00:00:00Z',
          },
        );
      }
      return _jsonResponse(
        statusCode: 500,
        body: <String, dynamic>{'detail': 'unexpected'},
      );
    });
    client.raw.httpClientAdapter = adapter;
    return _Harness(client: client, adapter: adapter);
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
