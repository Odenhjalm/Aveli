import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';

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

    test('accepts canonical null cover without fallback authority', () {
      final summary = CourseSummary.fromResponse(
        _coursePayload(cover: null, coverMediaId: 'media-1'),
      );

      expect(summary.coverMediaId, 'media-1');
      expect(summary.cover, isNull);
    });

    test('rejects placeholder cover objects', () {
      expect(
        () => CourseSummary.fromResponse(
          _coursePayload(
            cover: const {
              'media_id': 'media-1',
              'state': 'uploaded',
              'resolved_url': null,
            },
          ),
        ),
        throwsStateError,
      );
    });

    test('rejects legacy alternate cover fields', () {
      expect(
        () => CourseSummary.fromResponse(
          _coursePayload(
            cover: null,
            extra: const {
              'resolved_cover_url': 'https://cdn.test/legacy-cover.jpg',
            },
          ),
        ),
        throwsStateError,
      );
    });

    test('does not infer intro access from group position', () {
      final sellablePositionZero = CourseSummary.fromResponse(
        _coursePayload(
          priceCents: 9900,
          groupPosition: 0,
          requiredEnrollmentSource: 'purchase',
          enrollable: false,
          purchasable: true,
        ),
      );
      final freeNonZero = CourseSummary.fromResponse(
        _coursePayload(
          priceCents: 0,
          groupPosition: 2,
          requiredEnrollmentSource: 'intro_enrollment',
          enrollable: true,
          purchasable: false,
        ),
      );

      expect(sellablePositionZero.isIntroCourse, isFalse);
      expect(freeNonZero.isIntroCourse, isTrue);
    });

    test('rejects legacy step progression field', () {
      expect(
        () => CourseSummary.fromResponse(
          _coursePayload(extra: const {'step': 'intro'}),
        ),
        throwsStateError,
      );
    });

    test('preserves backend-authored teacher identity', () {
      final summary = CourseSummary.fromResponse(_coursePayload());

      expect(summary.teacher, isNotNull);
      expect(summary.teacher!.userId, 'teacher-1');
      expect(summary.teacher!.displayName, 'Aveli Teacher');
    });

    test(
      'rejects alternate teacher fields without canonical teacher object',
      () {
        final payload = _coursePayload(
          extra: const {'teacher_display_name': 'Aveli Teacher'},
        )..remove('teacher');

        expect(() => CourseSummary.fromResponse(payload), throwsStateError);
      },
    );

    test('rejects mixed canonical cover objects with legacy fields', () {
      expect(
        () => CourseSummary.fromResponse(
          _coursePayload(
            cover: const {
              'media_id': 'media-1',
              'state': 'ready',
              'resolved_url': '/api/files/public-media/course-cover.png',
              'playback_object_path': 'media/derived/cover/course.jpg',
            },
          ),
        ),
        throwsStateError,
      );
    });
  });

  group('CoursesRepository course cover reads', () {
    test('fetchPublishedCourses maps canonical cover from /courses', () async {
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/courses') {
          return _jsonResponse(
            statusCode: 200,
            body: {
              'items': [_coursePayload()],
            },
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = _repository(adapter);

      final courses = await repo.fetchPublishedCourses();

      expect(courses, hasLength(1));
      expect(courses.single.cover?.mediaId, 'media-1');
      expect(
        courses.single.cover?.resolvedUrl,
        '/api/files/public-media/course-cover.png',
      );
      expect(adapter.requestsFor('/courses'), hasLength(1));
    });

    test('myEnrolledCourses maps canonical cover from /courses/me', () async {
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/courses/me') {
          return _jsonResponse(
            statusCode: 200,
            body: {
              'items': [_coursePayload()],
            },
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = _repository(adapter);

      final courses = await repo.myEnrolledCourses();

      expect(courses, hasLength(1));
      expect(courses.single.cover?.mediaId, 'media-1');
      expect(
        courses.single.cover?.resolvedUrl,
        '/api/files/public-media/course-cover.png',
      );
      expect(adapter.requestsFor('/courses/me'), hasLength(1));
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
      expect(state.groupPosition, 0);
      expect(state.requiredEnrollmentSource, 'purchase');
      expect(state.enrollable, isFalse);
      expect(state.purchasable, isTrue);
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
      expect(state.enrollable, isFalse);
      expect(state.purchasable, isTrue);
      expect(state.hasEnrollment, isFalse);
      expect(state.enrollment, isNull);
      expect(adapter.requestsFor('/courses/course-2/access'), hasLength(1));
    });

    test('rejects legacy step progression field', () {
      expect(
        () => CourseAccessData.fromResponse(
          _accessPayload(extra: const {'step': 'intro'}),
        ),
        throwsStateError,
      );
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
              'short_description': 'Backend-authored course description',
            },
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = _repository(adapter);

      final detail = await repo.fetchCourseDetailBySlug(slug);

      expect(detail.course.slug, slug);
      expect(detail.course.teacher?.displayName, 'Aveli Teacher');
      expect(detail.shortDescription, 'Backend-authored course description');
      expect(
        detail.lessons.map((lesson) => lesson.lessonTitle),
        orderedEquals(['First', 'Second']),
      );
      expect(adapter.requestsFor('/courses/by-slug/$slug'), hasLength(1));
      expect(adapter.requestsFor('/courses/course-1/access'), isEmpty);
    });

    test('detail rejects legacy alternate cover fields', () async {
      const slug = 'legacy-course';
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/courses/by-slug/$slug') {
          return _jsonResponse(
            statusCode: 200,
            body: {
              'course': _coursePayload(
                slug: slug,
                cover: null,
                extra: const {
                  'resolved_cover_url': 'https://cdn.test/legacy-cover.jpg',
                },
              ),
              'lessons': const [],
              'short_description': null,
            },
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = _repository(adapter);

      await expectLater(
        repo.fetchCourseDetailBySlug(slug),
        throwsA(isA<AppFailure>()),
      );
      expect(adapter.requestsFor('/courses/by-slug/$slug'), hasLength(1));
    });
  });

  group('CoursesRepository.fetchLessonDetail', () {
    test('maps null lesson body as safe absence', () async {
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/courses/lessons/lesson-1') {
          return _jsonResponse(statusCode: 200, body: _lessonPayload());
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = _repository(adapter);

      final detail = await repo.fetchLessonDetail('lesson-1');

      expect(detail.lesson.contentMarkdown, isNull);
      expect(detail.media, isEmpty);
      expect(adapter.requestsFor('/courses/lessons/lesson-1'), hasLength(1));
    });

    test('wraps malformed lesson payload before render', () async {
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/courses/lessons/lesson-1') {
          return _jsonResponse(
            statusCode: 200,
            body: _lessonPayload(
              lesson: const {
                'id': 'lesson-1',
                'course_id': 'course-1',
                'lesson_title': '',
                'position': 1,
                'content_markdown': '# Lesson',
              },
            ),
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = _repository(adapter);

      await expectLater(
        repo.fetchLessonDetail('lesson-1'),
        throwsA(isA<AppFailure>()),
      );
      expect(adapter.requestsFor('/courses/lessons/lesson-1'), hasLength(1));
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

Map<String, Object?> _coursePayload({
  String slug = 'aveli-course',
  String? coverMediaId = 'media-1',
  Object? cover = _defaultCover,
  int groupPosition = 0,
  int? priceCents = 0,
  String? requiredEnrollmentSource = 'intro_enrollment',
  bool enrollable = true,
  bool purchasable = false,
  Map<String, Object?> extra = const {},
}) {
  return {
    'id': 'course-1',
    'slug': slug,
    'title': 'Aveli 101',
    'teacher': const {'user_id': 'teacher-1', 'display_name': 'Aveli Teacher'},
    'group_position': groupPosition,
    'course_group_id': 'group-1',
    'cover_media_id': coverMediaId,
    'cover': cover,
    'price_amount_cents': priceCents,
    'drip_enabled': false,
    'drip_interval_days': null,
    'required_enrollment_source': requiredEnrollmentSource,
    'enrollable': enrollable,
    'purchasable': purchasable,
    ...extra,
  };
}

const Map<String, Object?> _defaultCover = {
  'media_id': 'media-1',
  'state': 'ready',
  'resolved_url': '/api/files/public-media/course-cover.png',
};

Map<String, Object?> _accessPayload({
  String courseId = 'course-1',
  Object? enrollment = _defaultEnrollment,
  String? requiredEnrollmentSource = 'purchase',
  bool enrollable = false,
  bool purchasable = true,
  Map<String, Object?> extra = const {},
}) {
  return {
    'course_id': courseId,
    'group_position': 0,
    'required_enrollment_source': requiredEnrollmentSource,
    'enrollable': enrollable,
    'purchasable': purchasable,
    'enrollment': enrollment,
    ...extra,
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

Map<String, Object?> _lessonPayload({
  Object? lesson = const {
    'id': 'lesson-1',
    'course_id': 'course-1',
    'lesson_title': 'Lesson',
    'position': 1,
    'content_markdown': null,
  },
  Object? media = const [],
}) {
  return {
    'lesson': lesson,
    'course_id': 'course-1',
    'lessons': const [
      {'id': 'lesson-1', 'lesson_title': 'Lesson', 'position': 1},
    ],
    'media': media,
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
