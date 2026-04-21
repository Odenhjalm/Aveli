import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/widgets/home_player_upload_dialog.dart';
import 'package:aveli/features/studio/widgets/wav_upload_source.dart';

class _FakeApiClient extends Fake implements ApiClient {}

class _DialogStudioRepository extends StudioRepository {
  _DialogStudioRepository() : super(client: _FakeApiClient());

  int requestUploadUrlCalls = 0;
  int uploadCreateCalls = 0;
  int refreshCalls = 0;
  int createFromStorageCalls = 0;

  @override
  Future<Map<String, Object?>> requestHomePlayerUploadUrl({
    required String filename,
    required String mimeType,
    required int sizeBytes,
  }) async {
    requestUploadUrlCalls += 1;
    return <String, Object?>{
      'media_asset_id': 'media-1',
      'asset_state': 'pending_upload',
      'upload_session_id': 'upload-session-1',
      'upload_endpoint': '/api/media-assets/media-1/upload-bytes',
      'expires_at': '2026-04-21T12:00:00Z',
    };
  }

  @override
  Future<HomePlayerUploadItem> uploadHomePlayerUpload({
    required String title,
    required String mediaAssetId,
    bool active = true,
  }) async {
    uploadCreateCalls += 1;
    return HomePlayerUploadItem(
      id: 'upload-1',
      mediaAssetId: mediaAssetId,
      title: title,
      kind: 'audio',
      active: active,
      createdAt: DateTime.utc(2026, 4, 21, 10, 0),
      mediaState: 'uploaded',
    );
  }

  @override
  Future<Map<String, Object?>> refreshHomePlayerUploadUrl({
    required String objectPath,
    required String mimeType,
  }) {
    refreshCalls += 1;
    return super.refreshHomePlayerUploadUrl(
      objectPath: objectPath,
      mimeType: mimeType,
    );
  }

  @override
  Future<HomePlayerUploadItem> createHomePlayerUploadFromStorage({
    required String title,
    required String storagePath,
    required String contentType,
    required int byteSize,
    required String originalName,
    bool active = true,
    String storageBucket = 'course-media',
  }) {
    createFromStorageCalls += 1;
    return super.createHomePlayerUploadFromStorage(
      title: title,
      storagePath: storagePath,
      contentType: contentType,
      byteSize: byteSize,
      originalName: originalName,
      active: active,
      storageBucket: storageBucket,
    );
  }
}

void main() {
  testWidgets(
    'upload dialog uses canonical repository methods and keeps blocked methods unused',
    (tester) async {
      final studioRepo = _DialogStudioRepository();
      final harness = await _PipelineHarness.create();
      final pipelineRepo = MediaPipelineRepository(client: harness.client);
      final file = WavUploadFile(
        fs.XFile.fromData(
          Uint8List.fromList(<int>[1, 2, 3, 4]),
          name: 'demo.mp3',
          mimeType: 'audio/mpeg',
        ),
        'audio/mpeg',
        4,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studioRepositoryProvider.overrideWithValue(studioRepo),
            mediaPipelineRepositoryProvider.overrideWithValue(pipelineRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return FilledButton(
                    onPressed: () {
                      showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => HomePlayerUploadDialog(
                          file: file,
                          title: 'Morgonljud',
                          contentType: 'audio/mpeg',
                        ),
                      );
                    },
                    child: const Text('Öppna dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Öppna dialog'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(studioRepo.requestUploadUrlCalls, 1);
      expect(studioRepo.uploadCreateCalls, 1);
      expect(studioRepo.refreshCalls, 0);
      expect(studioRepo.createFromStorageCalls, 0);
      expect(find.text('Laddar upp ljud'), findsNothing);

      final uploadRequests = harness.adapter.requestsFor(
        '/api/media-assets/media-1/upload-bytes',
      );
      expect(uploadRequests, hasLength(1));
      expect(uploadRequests.single.method, 'PUT');

      final completionRequests = harness.adapter.requestsFor(
        '/api/media-assets/media-1/upload-completion',
      );
      expect(completionRequests, hasLength(1));
      expect(completionRequests.single.method, 'POST');

      final statusRequests = harness.adapter.requestsFor(
        '/api/media-assets/media-1/status',
      );
      expect(statusRequests, hasLength(1));
      expect(statusRequests.single.method, 'GET');
    },
  );
}

class _PipelineHarness {
  _PipelineHarness({required this.client, required this.adapter});

  final ApiClient client;
  final _RecordingAdapter adapter;

  static Future<_PipelineHarness> create() async {
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
      if (options.path == '/api/media-assets/media-1/upload-bytes' &&
          options.method.toUpperCase() == 'PUT') {
        return _jsonResponse(statusCode: 200, body: const <String, Object?>{});
      }
      if (options.path == '/api/media-assets/media-1/upload-completion' &&
          options.method.toUpperCase() == 'POST') {
        return _jsonResponse(
          statusCode: 200,
          body: <String, Object?>{
            'media_asset_id': 'media-1',
            'asset_state': 'uploaded',
          },
        );
      }
      if (options.path == '/api/media-assets/media-1/status' &&
          options.method.toUpperCase() == 'GET') {
        return _jsonResponse(
          statusCode: 200,
          body: <String, Object?>{
            'media_asset_id': 'media-1',
            'asset_state': 'ready',
          },
        );
      }
      return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
    });
    client.raw.httpClientAdapter = adapter;
    return _PipelineHarness(client: client, adapter: adapter);
  }
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
