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
    'createCourse posts only canonical create fields and adopts backend response',
    () async {
      final harness = await _Harness.create();
      final repo = StudioRepository(client: harness.client);

      final course = await repo.createCourse(
        title: 'Client draft',
        slug: 'client-draft',
        courseGroupId: '11111111-1111-1111-1111-111111111111',
        groupPosition: 0,
        priceAmountCents: 49000,
        dripEnabled: false,
        dripIntervalDays: null,
        coverMediaId: null,
      );

      expect(course.id, '22222222-2222-2222-2222-222222222222');
      expect(course.title, 'Backend draft');
      expect(course.slug, 'backend-draft');
      expect(course.courseGroupId, '11111111-1111-1111-1111-111111111111');
      expect(course.groupPosition, 0);
      expect(course.priceAmountCents, 49000);
      expect(course.dripEnabled, isFalse);
      expect(course.dripIntervalDays, isNull);
      expect(course.coverMediaId, isNull);

      final requests = harness.adapter.requestsFor('/studio/courses');
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');

      final payload = Map<String, dynamic>.from(requests.single.data as Map);
      expect(payload, {
        'title': 'Client draft',
        'slug': 'client-draft',
        'course_group_id': '11111111-1111-1111-1111-111111111111',
        'group_position': 0,
        'price_amount_cents': 49000,
        'drip_enabled': false,
        'drip_interval_days': null,
        'cover_media_id': null,
      });
      expect(payload.containsKey('content_ready'), isFalse);
      expect(payload.containsKey('sellable'), isFalse);
      expect(payload.containsKey('stripe_product_id'), isFalse);
      expect(payload.containsKey('active_stripe_price_id'), isFalse);
      expect(payload.containsKey('required_enrollment_source'), isFalse);
      expect(payload.containsKey('teacher_id'), isFalse);
    },
  );

  test(
    'publishCourse posts canonical publish request and adopts backend response',
    () async {
      final harness = await _Harness.create();
      final repo = StudioRepository(client: harness.client);

      final course = await repo.publishCourse(
        '33333333-3333-3333-3333-333333333333',
      );

      expect(course.id, '33333333-3333-3333-3333-333333333333');
      expect(course.title, 'Backend published');
      expect(course.slug, 'backend-published');

      final requests = harness.adapter.requestsFor(
        '/studio/courses/33333333-3333-3333-3333-333333333333/publish',
      );
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.data, isNull);
    },
  );
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
      if (options.path == '/studio/courses' &&
          options.method.toUpperCase() == 'POST') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'id': '22222222-2222-2222-2222-222222222222',
            'slug': 'backend-draft',
            'title': 'Backend draft',
            'course_group_id': '11111111-1111-1111-1111-111111111111',
            'group_position': 0,
            'cover_media_id': null,
            'cover': null,
            'price_amount_cents': 49000,
            'drip_enabled': false,
            'drip_interval_days': null,
          },
        );
      }
      if (options.path ==
              '/studio/courses/33333333-3333-3333-3333-333333333333/publish' &&
          options.method.toUpperCase() == 'POST') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'id': '33333333-3333-3333-3333-333333333333',
            'slug': 'backend-published',
            'title': 'Backend published',
            'course_group_id': '11111111-1111-1111-1111-111111111111',
            'group_position': 0,
            'cover_media_id': null,
            'cover': null,
            'price_amount_cents': 49000,
            'drip_enabled': false,
            'drip_interval_days': null,
          },
        );
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
