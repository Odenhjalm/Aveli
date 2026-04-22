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

  test('createCourse posts drip fields when enabled', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    final course = await repo.createCourse(
      title: 'Client drip draft',
      slug: 'client-drip-draft',
      courseGroupId: '11111111-1111-1111-1111-111111111111',
      priceAmountCents: 49000,
      dripEnabled: true,
      dripIntervalDays: 7,
      coverMediaId: null,
    );

    expect(course.dripEnabled, isTrue);
    expect(course.dripIntervalDays, 7);

    final requests = harness.adapter.requestsFor('/studio/courses');
    expect(requests, hasLength(1));
    final payload = Map<String, dynamic>.from(requests.single.data as Map);
    expect(payload['drip_enabled'], isTrue);
    expect(payload['drip_interval_days'], 7);
    expect(payload.containsKey('current_unlock_position'), isFalse);
    expect(payload.containsKey('drip_started_at'), isFalse);
  });

  test('updateCourse rejects raw family transition fields', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    await expectLater(
      repo.updateCourse('44444444-4444-4444-4444-444444444444', {
        'group_position': 1,
      }),
      throwsA(isA<UnsupportedError>()),
    );

    expect(
      harness.adapter.requestsFor(
        '/studio/courses/44444444-4444-4444-4444-444444444444',
      ),
      isEmpty,
    );
  });

  test('reorderCourseWithinFamily posts explicit reorder intent', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    final course = await repo.reorderCourseWithinFamily(
      '55555555-5555-5555-5555-555555555555',
      groupPosition: 0,
    );

    expect(course.id, '55555555-5555-5555-5555-555555555555');
    expect(course.groupPosition, 0);

    final requests = harness.adapter.requestsFor(
      '/studio/courses/55555555-5555-5555-5555-555555555555/reorder',
    );
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(Map<String, dynamic>.from(requests.single.data as Map), {
      'group_position': 0,
    });
  });

  test('moveCourseToFamily posts explicit move intent', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    final course = await repo.moveCourseToFamily(
      '66666666-6666-6666-6666-666666666666',
      courseGroupId: '77777777-7777-7777-7777-777777777777',
    );

    expect(course.id, '66666666-6666-6666-6666-666666666666');
    expect(course.courseGroupId, '77777777-7777-7777-7777-777777777777');
    expect(course.groupPosition, 2);

    final requests = harness.adapter.requestsFor(
      '/studio/courses/66666666-6666-6666-6666-666666666666/move-family',
    );
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(Map<String, dynamic>.from(requests.single.data as Map), {
      'course_group_id': '77777777-7777-7777-7777-777777777777',
    });
  });

  test('myCourseFamilies reads canonical family list', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    final families = await repo.myCourseFamilies();

    expect(families, hasLength(2));
    expect(families.first.id, '11111111-1111-1111-1111-111111111111');
    expect(families.first.name, 'Tarot Foundations');
    expect(families.first.courseCount, 2);

    final requests = harness.adapter.requestsFor('/studio/course-families');
    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
  });

  test('createCourseFamily posts canonical family create payload', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    final family = await repo.createCourseFamily(name: 'New Family');

    expect(family.id, '88888888-8888-8888-8888-888888888888');
    expect(family.name, 'New Family');
    expect(family.courseCount, 0);

    final requests = harness.adapter.requestsFor('/studio/course-families');
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(Map<String, dynamic>.from(requests.single.data as Map), {
      'name': 'New Family',
    });
  });

  test('renameCourseFamily patches canonical family rename payload', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    final family = await repo.renameCourseFamily(
      '88888888-8888-8888-8888-888888888888',
      name: 'Renamed Family',
    );

    expect(family.id, '88888888-8888-8888-8888-888888888888');
    expect(family.name, 'Renamed Family');
    expect(family.courseCount, 1);

    final requests = harness.adapter.requestsFor(
      '/studio/course-families/88888888-8888-8888-8888-888888888888',
    );
    expect(requests, hasLength(1));
    expect(requests.single.method, 'PATCH');
    expect(Map<String, dynamic>.from(requests.single.data as Map), {
      'name': 'Renamed Family',
    });
  });

  test('deleteCourseFamily uses canonical family delete route', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    await repo.deleteCourseFamily('12121212-1212-1212-1212-121212121212');

    final requests = harness.adapter.requestsFor(
      '/studio/course-families/12121212-1212-1212-1212-121212121212',
    );
    expect(requests, hasLength(1));
    expect(requests.single.method, 'DELETE');
    expect(requests.single.data, isNull);
  });

  test('myCourses reads studio drip authoring summary', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    final courses = await repo.myCourses();

    expect(courses, hasLength(1));
    expect(courses.single.id, '99999999-9999-9999-9999-999999999999');
    expect(courses.single.dripAuthoring.mode.apiValue, 'custom_lesson_offsets');
    expect(courses.single.dripAuthoring.scheduleLocked, isFalse);
    expect(courses.single.dripAuthoring.customSchedule, isNull);

    final requests = harness.adapter.requestsFor('/studio/courses');
    expect(requests.where((request) => request.method == 'GET'), hasLength(1));
  });

  test('fetchCourseMeta reads studio drip authoring detail', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    final course = await repo.fetchCourseMeta(
      '99999999-9999-9999-9999-999999999999',
    );

    expect(course.dripAuthoring.mode.apiValue, 'custom_lesson_offsets');
    expect(course.dripAuthoring.customScheduleRows, hasLength(2));
    expect(course.dripAuthoring.customScheduleRows.first.lessonId, 'lesson-1');
    expect(course.dripAuthoring.customScheduleRows.last.unlockOffsetDays, 3);
  });

  test('updateCourse rejects drip authoring patch fields', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    await expectLater(
      repo.updateCourse('44444444-4444-4444-4444-444444444444', {
        'drip_enabled': true,
      }),
      throwsA(isA<UnsupportedError>()),
    );

    expect(
      harness.adapter.requestsFor(
        '/studio/courses/44444444-4444-4444-4444-444444444444',
      ),
      isEmpty,
    );
  });

  test('updateCourseDripAuthoring puts canonical dedicated payload', () async {
    final harness = await _Harness.create();
    final repo = StudioRepository(client: harness.client);

    final course = await repo.updateCourseDripAuthoring(
      '99999999-9999-9999-9999-999999999999',
      <String, Object?>{
        'mode': 'custom_lesson_offsets',
        'custom_schedule': <String, Object?>{
          'rows': <Map<String, Object?>>[
            {'lesson_id': 'lesson-1', 'unlock_offset_days': 0},
            {'lesson_id': 'lesson-2', 'unlock_offset_days': 5},
          ],
        },
      },
    );

    expect(course.dripAuthoring.mode.apiValue, 'custom_lesson_offsets');
    expect(course.dripAuthoring.customScheduleRows.last.unlockOffsetDays, 5);

    final requests = harness.adapter.requestsFor(
      '/studio/courses/99999999-9999-9999-9999-999999999999/drip-authoring',
    );
    expect(requests, hasLength(1));
    expect(requests.single.method, 'PUT');
    expect(Map<String, dynamic>.from(requests.single.data as Map), {
      'mode': 'custom_lesson_offsets',
      'custom_schedule': {
        'rows': [
          {'lesson_id': 'lesson-1', 'unlock_offset_days': 0},
          {'lesson_id': 'lesson-2', 'unlock_offset_days': 5},
        ],
      },
    });
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
      if (options.path == '/studio/courses' &&
          options.method.toUpperCase() == 'GET') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'items': [
              {
                'id': '99999999-9999-9999-9999-999999999999',
                'slug': 'backend-summary',
                'title': 'Backend summary',
                'course_group_id': '11111111-1111-1111-1111-111111111111',
                'group_position': 1,
                'cover_media_id': null,
                'cover': null,
                'price_amount_cents': 49000,
                'teacher': null,
                'required_enrollment_source': null,
                'enrollable': true,
                'purchasable': true,
                'drip_authoring': {
                  'mode': 'custom_lesson_offsets',
                  'schedule_locked': false,
                  'lock_reason': null,
                  'legacy_uniform': null,
                },
              },
            ],
          },
        );
      }
      if (options.path == '/studio/courses' &&
          options.method.toUpperCase() == 'POST') {
        final payload = Map<String, dynamic>.from(options.data as Map);
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
            'drip_enabled': payload['drip_enabled'] as bool? ?? false,
            'drip_interval_days': payload['drip_interval_days'] as int?,
          },
        );
      }
      if (options.path ==
              '/studio/courses/99999999-9999-9999-9999-999999999999' &&
          options.method.toUpperCase() == 'GET') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'id': '99999999-9999-9999-9999-999999999999',
            'slug': 'backend-detail',
            'title': 'Backend detail',
            'course_group_id': '11111111-1111-1111-1111-111111111111',
            'group_position': 1,
            'cover_media_id': null,
            'cover': null,
            'price_amount_cents': 49000,
            'teacher': null,
            'required_enrollment_source': null,
            'enrollable': true,
            'purchasable': true,
            'drip_authoring': {
              'mode': 'custom_lesson_offsets',
              'schedule_locked': false,
              'lock_reason': null,
              'legacy_uniform': null,
              'custom_schedule': {
                'rows': [
                  {'lesson_id': 'lesson-1', 'unlock_offset_days': 0},
                  {'lesson_id': 'lesson-2', 'unlock_offset_days': 3},
                ],
              },
            },
          },
        );
      }
      if (options.path == '/studio/course-families' &&
          options.method.toUpperCase() == 'GET') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'items': [
              {
                'id': '11111111-1111-1111-1111-111111111111',
                'name': 'Tarot Foundations',
                'teacher_id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                'created_at': '2026-01-01T00:00:00Z',
                'course_count': 2,
              },
              {
                'id': '77777777-7777-7777-7777-777777777777',
                'name': 'Breathwork Flow',
                'teacher_id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                'created_at': '2026-01-02T00:00:00Z',
                'course_count': 1,
              },
            ],
          },
        );
      }
      if (options.path == '/studio/course-families' &&
          options.method.toUpperCase() == 'POST') {
        return _jsonResponse(
          statusCode: 201,
          body: {
            'id': '88888888-8888-8888-8888-888888888888',
            'name': 'New Family',
            'teacher_id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'created_at': '2026-01-03T00:00:00Z',
            'course_count': 0,
          },
        );
      }
      if (options.path ==
              '/studio/course-families/88888888-8888-8888-8888-888888888888' &&
          options.method.toUpperCase() == 'PATCH') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'id': '88888888-8888-8888-8888-888888888888',
            'name': 'Renamed Family',
            'teacher_id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'created_at': '2026-01-03T00:00:00Z',
            'course_count': 1,
          },
        );
      }
      if (options.path ==
              '/studio/course-families/12121212-1212-1212-1212-121212121212' &&
          options.method.toUpperCase() == 'DELETE') {
        return _jsonResponse(statusCode: 200, body: {'deleted': true});
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
      if (options.path ==
              '/studio/courses/99999999-9999-9999-9999-999999999999/drip-authoring' &&
          options.method.toUpperCase() == 'PUT') {
        final payload = Map<String, dynamic>.from(options.data as Map);
        return _jsonResponse(
          statusCode: 200,
          body: {
            'id': '99999999-9999-9999-9999-999999999999',
            'slug': 'backend-detail',
            'title': 'Backend detail',
            'course_group_id': '11111111-1111-1111-1111-111111111111',
            'group_position': 1,
            'cover_media_id': null,
            'cover': null,
            'price_amount_cents': 49000,
            'teacher': null,
            'required_enrollment_source': null,
            'enrollable': true,
            'purchasable': true,
            'drip_authoring': {
              'mode': payload['mode'],
              'schedule_locked': false,
              'lock_reason': null,
              'legacy_uniform': payload['legacy_uniform'],
              'custom_schedule': payload['custom_schedule'],
            },
          },
        );
      }
      if (options.path ==
              '/studio/courses/55555555-5555-5555-5555-555555555555/reorder' &&
          options.method.toUpperCase() == 'POST') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'id': '55555555-5555-5555-5555-555555555555',
            'slug': 'backend-reordered',
            'title': 'Backend reordered',
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
              '/studio/courses/66666666-6666-6666-6666-666666666666/move-family' &&
          options.method.toUpperCase() == 'POST') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'id': '66666666-6666-6666-6666-666666666666',
            'slug': 'backend-moved',
            'title': 'Backend moved',
            'course_group_id': '77777777-7777-7777-7777-777777777777',
            'group_position': 2,
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
