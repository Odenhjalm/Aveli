import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';

void main() {
  test('fetchHomePlayerLibrary parses canonical backend response', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    final payload = await repo.fetchHomePlayerLibrary();

    expect(payload.uploads, hasLength(1));
    expect(payload.uploads.single.id, 'upload-1');
    expect(payload.uploads.single.mediaAssetId, 'media-1');
    expect(payload.uploads.single.title, 'Direct audio');
    expect(payload.uploads.single.kind, 'audio');
    expect(payload.uploads.single.active, isTrue);
    expect(payload.uploads.single.mediaState, 'processing');
    expect(payload.uploads.single.mediaId, isNull);
    expect(payload.uploads.single.originalName, isNull);
    expect(payload.uploads.single.contentType, isNull);
    expect(payload.uploads.single.byteSize, isNull);

    expect(payload.courseLinks, hasLength(1));
    expect(payload.courseLinks.single.id, 'link-1');
    expect(payload.courseLinks.single.lessonMediaId, 'lesson-media-1');
    expect(payload.courseLinks.single.title, 'Linked audio');
    expect(payload.courseLinks.single.courseTitle, 'Course title');
    expect(payload.courseLinks.single.enabled, isTrue);
    expect(
      payload.courseLinks.single.status,
      HomePlayerCourseLinkStatus.courseUnpublished,
    );

    expect(payload.courseMedia, hasLength(1));
    expect(payload.courseMedia.single.id, 'lesson-media-1');
    expect(payload.courseMedia.single.lessonId, 'lesson-1');
    expect(payload.courseMedia.single.courseId, 'course-1');
    expect(payload.courseMedia.single.courseSlug, 'course-title');
    expect(payload.courseMedia.single.kind, 'audio');
    expect(payload.courseMedia.single.media, isNull);
    expect(
      payload.textBundle.requireValue(
        'studio_editor.profile_media.home_player_library_title',
      ),
      'Home-spelarens bibliotek',
    );

    final requests = harness.adapter.requestsFor('/studio/home-player/library');
    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
  });

  test(
    'home player upload repository uses canonical backend endpoints',
    () async {
      final harness = await _Harness.create();
      final repo = StudioRepository(client: harness.client);

      final uploadUrl = await repo.requestHomePlayerUploadUrl(
        filename: 'demo.wav',
        mimeType: 'audio/wav',
        sizeBytes: 1234,
      );
      final created = await repo.uploadHomePlayerUpload(
        title: 'Demo audio',
        mediaAssetId: 'media-1',
        active: true,
      );
      final updated = await repo.updateHomePlayerUpload(
        'upload-1',
        active: false,
      );
      await repo.deleteHomePlayerUpload('upload-1');

      expect(uploadUrl['media_asset_id'], 'media-1');
      expect(uploadUrl['asset_state'], 'pending_upload');
      expect(
        uploadUrl['upload_endpoint'],
        '/api/media-assets/media-1/upload-sessions/upload-session-1/chunks',
      );
      expect(
        uploadUrl['session_status_endpoint'],
        '/api/media-assets/media-1/upload-sessions/upload-session-1/status',
      );
      expect(
        uploadUrl['finalize_endpoint'],
        '/api/media-assets/media-1/upload-sessions/upload-session-1/finalize',
      );
      expect(uploadUrl['chunk_size'], 8 * 1024 * 1024);
      expect(uploadUrl['expected_chunks'], 1);

      expect(created.id, 'upload-1');
      expect(created.mediaAssetId, 'media-1');
      expect(created.title, 'Demo audio');
      expect(created.active, isTrue);
      expect(created.mediaState, 'uploaded');

      expect(updated.id, 'upload-1');
      expect(updated.active, isFalse);
      expect(updated.mediaAssetId, 'media-1');

      final uploadUrlRequests = harness.adapter.requestsFor(
        '/api/home-player/media-assets/upload-url',
      );
      expect(uploadUrlRequests, hasLength(1));
      expect(uploadUrlRequests.single.method, 'POST');
      expect(Map<String, dynamic>.from(uploadUrlRequests.single.data as Map), {
        'filename': 'demo.wav',
        'mime_type': 'audio/wav',
        'size_bytes': 1234,
      });

      final createRequests = harness.adapter.requestsFor(
        '/studio/home-player/uploads',
      );
      expect(createRequests, hasLength(1));
      expect(createRequests.single.method, 'POST');
      expect(Map<String, dynamic>.from(createRequests.single.data as Map), {
        'title': 'Demo audio',
        'media_asset_id': 'media-1',
        'active': true,
      });

      final uploadItemRequests = harness.adapter.requestsFor(
        '/studio/home-player/uploads/upload-1',
      );
      final updateRequests = uploadItemRequests
          .where((request) => request.method == 'PATCH')
          .toList(growable: false);
      expect(updateRequests, hasLength(1));
      expect(Map<String, dynamic>.from(updateRequests.single.data as Map), {
        'active': false,
      });
      final deleteRequests = uploadItemRequests
          .where((request) => request.method == 'DELETE')
          .toList(growable: false);
      expect(deleteRequests, hasLength(1));
    },
  );

  test(
    'home player course link repository uses canonical backend endpoints',
    () async {
      final harness = await _Harness.create();
      final repo = StudioRepository(client: harness.client);

      final created = await repo.createHomePlayerCourseLink(
        lessonMediaId: 'lesson-media-1',
        title: 'Linked audio',
        enabled: true,
      );
      final updated = await repo.updateHomePlayerCourseLink(
        'link-1',
        title: 'Updated link',
      );
      await repo.deleteHomePlayerCourseLink('link-1');

      expect(created.id, 'link-1');
      expect(created.lessonMediaId, 'lesson-media-1');
      expect(created.title, 'Linked audio');
      expect(created.courseTitle, 'Course title');
      expect(created.enabled, isTrue);

      expect(updated.id, 'link-1');
      expect(updated.title, 'Updated link');
      expect(updated.enabled, isFalse);

      final createRequests = harness.adapter.requestsFor(
        '/studio/home-player/course-links',
      );
      expect(createRequests, hasLength(1));
      expect(createRequests.single.method, 'POST');
      expect(Map<String, dynamic>.from(createRequests.single.data as Map), {
        'lesson_media_id': 'lesson-media-1',
        'title': 'Linked audio',
        'enabled': true,
      });

      final courseLinkRequests = harness.adapter.requestsFor(
        '/studio/home-player/course-links/link-1',
      );
      final updateRequests = courseLinkRequests
          .where((request) => request.method == 'PATCH')
          .toList(growable: false);
      expect(updateRequests, hasLength(1));
      expect(Map<String, dynamic>.from(updateRequests.single.data as Map), {
        'title': 'Updated link',
      });
      final deleteRequests = courseLinkRequests
          .where((request) => request.method == 'DELETE')
          .toList(growable: false);
      expect(deleteRequests, hasLength(1));
    },
  );

  test('blocked home player methods remain unsupported', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    expect(
      repo.refreshHomePlayerUploadUrl(
        objectPath: 'media/source/audio/demo.wav',
        mimeType: 'audio/wav',
      ),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      repo.createHomePlayerUploadFromStorage(
        title: 'Demo audio',
        storagePath: 'media/source/audio/demo.wav',
        contentType: 'audio/wav',
        byteSize: 1234,
        originalName: 'demo.wav',
      ),
      throwsA(isA<UnsupportedError>()),
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
      if (options.path == '/studio/home-player/library' &&
          options.method.toUpperCase() == 'GET') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'uploads': [
              {
                'id': 'upload-1',
                'media_asset_id': 'media-1',
                'title': 'Direct audio',
                'active': true,
                'created_at': '2026-04-21T10:00:00Z',
                'updated_at': '2026-04-21T10:05:00Z',
                'kind': 'audio',
                'media_state': 'processing',
              },
            ],
            'course_links': [
              {
                'id': 'link-1',
                'lesson_media_id': 'lesson-media-1',
                'title': 'Linked audio',
                'course_title': 'Course title',
                'enabled': true,
                'created_at': '2026-04-21T09:00:00Z',
                'updated_at': '2026-04-21T09:05:00Z',
                'kind': 'audio',
                'status': 'course_unpublished',
              },
            ],
            'course_media': [
              {
                'id': 'lesson-media-1',
                'lesson_id': 'lesson-1',
                'lesson_title': 'Lesson title',
                'course_id': 'course-1',
                'course_title': 'Course title',
                'course_slug': 'course-title',
                'kind': 'audio',
                'content_type': null,
                'duration_seconds': null,
                'position': 1,
                'created_at': null,
                'media': null,
              },
            ],
            'text_bundle': {
              'studio_editor.profile_media.home_player_library_title': {
                'surface_id': 'TXT-SURF-071',
                'text_id':
                    'studio_editor.profile_media.home_player_library_title',
                'authority_class': 'contract_text',
                'canonical_owner': 'backend_text_catalog',
                'source_contract':
                    'actual_truth/contracts/backend_text_catalog_contract.md',
                'backend_namespace': 'backend_text_catalog.studio_editor',
                'api_surface': '/studio/home-player/library',
                'delivery_surface': '/studio/home-player/library',
                'render_surface':
                    'frontend/lib/features/studio/presentation/profile_media_page.dart',
                'language': 'sv',
                'interpolation_keys': const [],
                'forbidden_render_fields': const [],
                'value': 'Home-spelarens bibliotek',
              },
            },
          },
        );
      }
      if (options.path == '/api/home-player/media-assets/upload-url' &&
          options.method.toUpperCase() == 'POST') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'media_asset_id': 'media-1',
            'asset_state': 'pending_upload',
            'upload_session_id': 'upload-session-1',
            'upload_endpoint':
                '/api/media-assets/media-1/upload-sessions/upload-session-1/chunks',
            'session_status_endpoint':
                '/api/media-assets/media-1/upload-sessions/upload-session-1/status',
            'finalize_endpoint':
                '/api/media-assets/media-1/upload-sessions/upload-session-1/finalize',
            'chunk_size': 8 * 1024 * 1024,
            'expected_chunks': 1,
            'expires_at': '2026-04-21T12:00:00Z',
          },
        );
      }
      if (options.path == '/studio/home-player/uploads' &&
          options.method.toUpperCase() == 'POST') {
        return _jsonResponse(
          statusCode: 201,
          body: {
            'id': 'upload-1',
            'teacher_id': 'teacher-1',
            'media_asset_id': 'media-1',
            'title': 'Demo audio',
            'kind': 'audio',
            'active': true,
            'created_at': '2026-04-21T10:00:00Z',
            'updated_at': '2026-04-21T10:05:00Z',
            'media_state': 'uploaded',
          },
        );
      }
      if (options.path == '/studio/home-player/uploads/upload-1' &&
          options.method.toUpperCase() == 'PATCH') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'id': 'upload-1',
            'teacher_id': 'teacher-1',
            'media_asset_id': 'media-1',
            'title': 'Demo audio',
            'kind': 'audio',
            'active': false,
            'created_at': '2026-04-21T10:00:00Z',
            'updated_at': '2026-04-21T10:06:00Z',
            'media_state': 'uploaded',
          },
        );
      }
      if (options.path == '/studio/home-player/uploads/upload-1' &&
          options.method.toUpperCase() == 'DELETE') {
        return _jsonResponse(statusCode: 204, body: const {});
      }
      if (options.path == '/studio/home-player/course-links' &&
          options.method.toUpperCase() == 'POST') {
        return _jsonResponse(
          statusCode: 201,
          body: {
            'id': 'link-1',
            'teacher_id': 'teacher-1',
            'lesson_media_id': 'lesson-media-1',
            'title': 'Linked audio',
            'course_title': 'Course title',
            'enabled': true,
            'status': 'active',
            'kind': 'audio',
            'created_at': '2026-04-21T09:00:00Z',
            'updated_at': '2026-04-21T09:05:00Z',
          },
        );
      }
      if (options.path == '/studio/home-player/course-links/link-1' &&
          options.method.toUpperCase() == 'PATCH') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'id': 'link-1',
            'teacher_id': 'teacher-1',
            'lesson_media_id': 'lesson-media-1',
            'title': 'Updated link',
            'course_title': 'Course title',
            'enabled': false,
            'status': 'active',
            'kind': 'audio',
            'created_at': '2026-04-21T09:00:00Z',
            'updated_at': '2026-04-21T09:06:00Z',
          },
        );
      }
      if (options.path == '/studio/home-player/course-links/link-1' &&
          options.method.toUpperCase() == 'DELETE') {
        return _jsonResponse(statusCode: 204, body: const {});
      }
      return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
    });
    client.raw.httpClientAdapter = adapter;
    return _Harness(client: client, adapter: adapter);
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
