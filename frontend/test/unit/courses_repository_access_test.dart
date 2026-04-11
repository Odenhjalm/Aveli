import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/shared/utils/course_journey_step.dart';

void main() {
  group('CourseSummary.fromResponse', () {
    test('preserves the backend-authored cover object', () {
      final summary = CourseSummary.fromResponse(_coursePayload());

      expect(summary.cover, isNotNull);
      expect(summary.cover!.mediaId, 'media-1');
      expect(
        summary.cover!.resolvedUrl,
        '/api/files/public-media/course-cover.png',
      );
    });
  });

  group('CoursesRepository.fetchCourseState', () {
    test('maps canonical enrollment-backed access state', () async {
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/courses/course-1/access') {
          return _jsonResponse(statusCode: 200, body: _accessPayload());
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = _repository(adapter);

      final state = await repo.fetchCourseState('course-1');

      expect(state.courseId, 'course-1');
      expect(state.courseStep, CourseJourneyStep.intro);
      expect(state.requiredEnrollmentSource, isNull);
      expect(state.hasEnrollment, isTrue);
      expect(state.enrollment!.source, 'purchase');
      expect(state.enrollment!.currentUnlockPosition, 1);
      expect(adapter.requestsFor('/courses/course-1/access'), hasLength(1));
    });

    test('maps absent enrollment without fallback access authority', () async {
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/courses/course-2/access') {
          return _jsonResponse(
            statusCode: 200,
            body: _accessPayload(
              courseId: 'course-2',
              enrollment: null,
              requiredEnrollmentSource: 'purchase',
            ),
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = _repository(adapter);

      final state = await repo.fetchCourseState('course-2');

      expect(state.courseId, 'course-2');
      expect(state.requiredEnrollmentSource, 'purchase');
      expect(state.hasEnrollment, isFalse);
      expect(state.enrollment, isNull);
      expect(adapter.requestsFor('/courses/course-2/access'), hasLength(1));
    });
  });

  group('CoursesRepository.fetchCourseDetailBySlug', () {
    test('maps canonical detail without access enrichment', () async {
      const slug = 'aveli-course';
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/courses/by-slug/$slug') {
          return _jsonResponse(
            statusCode: 200,
            body: {
              'course': _coursePayload(slug: slug),
              'lessons': [
                {'id': 'lesson-2', 'lesson_title': 'Second', 'position': 2},
                {'id': 'lesson-1', 'lesson_title': 'First', 'position': 1},
              ],
            },
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = _repository(adapter);

      final detail = await repo.fetchCourseDetailBySlug(slug);

      expect(detail.course.slug, slug);
      expect(
        detail.lessons.map((lesson) => lesson.lessonTitle),
        orderedEquals(['First', 'Second']),
      );
      expect(adapter.requestsFor('/courses/by-slug/$slug'), hasLength(1));
      expect(adapter.requestsFor('/courses/course-1/access'), isEmpty);
    });
  });
}

CoursesRepository _repository(_RecordingAdapter adapter) {
  final client = ApiClient(
    baseUrl: 'http://127.0.0.1:1',
    tokenStorage: TokenStorage(storage: _MemoryFlutterSecureStorage()),
  );
  client.raw.httpClientAdapter = adapter;
  return CoursesRepository(client: client);
}

Map<String, Object?> _coursePayload({String slug = 'aveli-course'}) {
  return {
    'id': 'course-1',
    'slug': slug,
    'title': 'Aveli 101',
    'step': 'intro',
    'course_group_id': 'group-1',
    'cover_media_id': 'media-1',
    'cover': {
      'media_id': 'media-1',
      'state': 'ready',
      'resolved_url': '/api/files/public-media/course-cover.png',
    },
    'price_amount_cents': 0,
    'drip_enabled': false,
    'drip_interval_days': null,
  };
}

Map<String, Object?> _accessPayload({
  String courseId = 'course-1',
  Object? enrollment = _defaultEnrollment,
  String? requiredEnrollmentSource,
}) {
  return {
    'course_id': courseId,
    'course_step': 'intro',
    'required_enrollment_source': requiredEnrollmentSource,
    'enrollment': enrollment,
  };
}

const Map<String, Object?> _defaultEnrollment = {
  'id': 'enrollment-1',
  'user_id': 'user-1',
  'course_id': 'course-1',
  'source': 'purchase',
  'granted_at': '2024-01-10T12:00:00Z',
  'drip_started_at': '2024-01-10T12:00:00Z',
  'current_unlock_position': 1,
};

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
