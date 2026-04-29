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

    test(
      'preserves backend intro authority fields without local derivation',
      () {
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
            requiredEnrollmentSource: 'intro',
            enrollable: true,
            purchasable: false,
          ),
        );

        expect(sellablePositionZero.requiredEnrollmentSource, 'purchase');
        expect(sellablePositionZero.enrollable, isFalse);
        expect(sellablePositionZero.purchasable, isTrue);
        expect(freeNonZero.requiredEnrollmentSource, 'intro');
        expect(freeNonZero.enrollable, isTrue);
        expect(freeNonZero.purchasable, isFalse);
      },
    );

    test('maps backend description and intro source classifier', () {
      final intro = CourseSummary.fromResponse(
        _coursePayload(
          description: 'Backend list description',
          requiredEnrollmentSource: 'intro',
        ),
      );
      final legacyFree = CourseSummary.fromResponse(
        _coursePayload(
          priceCents: null,
          requiredEnrollmentSource: 'intro_enrollment',
        ),
      );

      expect(intro.description, 'Backend list description');
      expect(intro.isIntroCourse, isTrue);
      expect(legacyFree.isIntroCourse, isFalse);
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

  group('CoursesRepository.fetchIntroSelectionState', () {
    test('calls canonical intro selection route and preserves order', () async {
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/courses/intro-selection') {
          return _jsonResponse(
            statusCode: 200,
            body: _introSelectionPayload(
              eligibleCourses: [
                _coursePayload(slug: 'second-intro', title: 'Second Intro'),
                _coursePayload(slug: 'first-intro', title: 'First Intro'),
              ],
            ),
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = _repository(adapter);

      final state = await repo.fetchIntroSelectionState();

      expect(state.selectionLocked, isFalse);
      expect(state.selectionLockReason, isNull);
      expect(
        state.eligibleCourses.map((course) => course.slug),
        orderedEquals(['second-intro', 'first-intro']),
      );
      expect(adapter.requestsFor('/courses/intro-selection'), hasLength(1));
    });
  });

  group('CoursesRepository.fetchCourseState', () {
    test('maps canonical enrollment-backed access state', () async {
      const nextUnlockAt = '2024-01-17T12:00:00Z';
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/courses/course-1/access') {
          return _jsonResponse(
            statusCode: 200,
            body: _accessPayload(nextUnlockAt: nextUnlockAt),
          );
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
      expect(state.isIntroCourse, isFalse);
      expect(state.selectionLocked, isFalse);
      expect(state.canAccess, isTrue);
      expect(state.nextUnlockAt, DateTime.parse(nextUnlockAt));
      expect(state.enrollment!.source, 'purchase');
      expect(state.enrollment!.unlockPosition, 1);
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
              canAccess: false,
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
      expect(state.isIntroCourse, isFalse);
      expect(state.selectionLocked, isFalse);
      expect(state.canAccess, isFalse);
      expect(state.enrollment, isNull);
      expect(adapter.requestsFor('/courses/course-2/access'), hasLength(1));
    });

    test('uses backend can_access even when enrollment exists', () async {
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/courses/course-3/access') {
          return _jsonResponse(
            statusCode: 200,
            body: _accessPayload(
              courseId: 'course-3',
              requiredEnrollmentSource: 'intro',
              enrollable: true,
              purchasable: false,
              isIntroCourse: true,
              canAccess: false,
              enrollment: _enrollmentPayload(source: 'intro'),
            ),
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = _repository(adapter);

      final state = await repo.fetchCourseState('course-3');

      expect(state.enrollment, isNotNull);
      expect(state.enrollment!.source, 'intro');
      expect(state.isIntroCourse, isTrue);
      expect(state.selectionLocked, isFalse);
      expect(state.canAccess, isFalse);
    });

    test('maps intro classification and selection lock fields', () async {
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/courses/course-4/access') {
          return _jsonResponse(
            statusCode: 200,
            body: _accessPayload(
              courseId: 'course-4',
              requiredEnrollmentSource: 'intro',
              enrollable: true,
              purchasable: false,
              isIntroCourse: true,
              selectionLocked: true,
              canAccess: false,
              enrollment: null,
            ),
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = _repository(adapter);

      final state = await repo.fetchCourseState('course-4');

      expect(state.isIntroCourse, isTrue);
      expect(state.selectionLocked, isTrue);
      expect(state.canAccess, isFalse);
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
              'description': 'Backend-authored course description',
            },
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = _repository(adapter);

      final detail = await repo.fetchCourseDetailBySlug(slug);

      expect(detail.course.slug, slug);
      expect(detail.course.teacher?.displayName, 'Aveli Teacher');
      expect(detail.description, 'Backend-authored course description');
      expect(
        detail.lessons.map((lesson) => lesson.lessonTitle),
        orderedEquals(['First', 'Second']),
      );
      expect(adapter.requestsFor('/courses/by-slug/$slug'), hasLength(1));
      expect(adapter.requestsFor('/courses/course-1/access'), isEmpty);
    });

    test(
      'maps legacy English course-not-found detail to Swedish failure',
      () async {
        const slug = 'missing-course';
        final adapter = _RecordingAdapter((options) {
          if (options.path == '/courses/by-slug/$slug') {
            return _jsonResponse(
              statusCode: 404,
              body: {'detail': 'Course not found'},
            );
          }
          return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
        });
        final repo = _repository(adapter);

        await expectLater(
          repo.fetchCourseDetailBySlug(slug),
          throwsA(
            isA<AppFailure>().having(
              (failure) => failure.message,
              'message',
              'Kursen kunde inte hittas.',
            ),
          ),
        );
        expect(adapter.requestsFor('/courses/by-slug/$slug'), hasLength(1));
      },
    );

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
              'description': null,
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

  group('CoursesRepository.fetchCourseEntryView', () {
    test(
      'calls canonical entry-view route and maps backend projections',
      () async {
        const slug = 'aveli-course';
        final adapter = _RecordingAdapter((options) {
          if (options.path == '/courses/$slug/entry-view') {
            return _jsonResponse(statusCode: 200, body: _entryViewPayload());
          }
          return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
        });
        final repo = _repository(adapter);

        final view = await repo.fetchCourseEntryView(slug);

        expect(view.course.slug, slug);
        expect(view.course.description, 'Backend-authored course description');
        expect(
          view.course.cover?.url,
          '/api/files/public-media/course-cover.png',
        );
        expect(view.access.isInAnyIntroDrip, isFalse);
        expect(view.cta.type, 'continue');
        expect(view.cta.actionType, 'lesson');
        expect(view.pricing?.formattedPrice, '990 kr');
        expect(view.nextRecommendedLesson?.id, 'lesson-1');
        expect(view.lessons.single.availability.state, 'unlocked');
        expect(view.lessons.single.progression.isNextRecommended, isTrue);
        expect(adapter.requestsFor('/courses/$slug/entry-view'), hasLength(1));
        expect(adapter.requestsFor('/courses/by-slug/$slug'), isEmpty);
        expect(adapter.requestsFor('/courses/course-1/access'), isEmpty);
      },
    );

    test('rejects lesson runtime content from entry-view responses', () async {
      const slug = 'aveli-course';
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/courses/$slug/entry-view') {
          return _jsonResponse(
            statusCode: 200,
            body: _entryViewPayload(
              lessons: [
                {
                  ..._defaultEntryLesson,
                  'content_document': const {'blocks': []},
                },
              ],
            ),
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = _repository(adapter);

      await expectLater(
        repo.fetchCourseEntryView(slug),
        throwsA(isA<AppFailure>()),
      );
    });

    test(
      'rejects media and resolved URL fields from entry-view responses',
      () async {
        const slug = 'aveli-course';
        final adapter = _RecordingAdapter((options) {
          if (options.path == '/courses/$slug/entry-view') {
            return _jsonResponse(
              statusCode: 200,
              body: _entryViewPayload(
                course: {
                  ..._defaultEntryCourse,
                  'cover': const {
                    'url': '/api/files/public-media/course-cover.png',
                    'alt': 'Course cover',
                    'resolved_url': '/api/files/public-media/course-cover.png',
                  },
                },
                lessons: [
                  {..._defaultEntryLesson, 'lesson_media_id': 'lesson-media-1'},
                ],
              ),
            );
          }
          return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
        });
        final repo = _repository(adapter);

        await expectLater(
          repo.fetchCourseEntryView(slug),
          throwsA(isA<AppFailure>()),
        );
      },
    );
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

      expect(detail.lesson.contentDocument?.blocks, isEmpty);
      expect(detail.media, isEmpty);
      expect(adapter.requestsFor('/courses/lessons/lesson-1'), hasLength(1));
    });

    test('wraps malformed lesson payload before render', () async {
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/courses/lessons/lesson-1') {
          return _jsonResponse(
            statusCode: 200,
            body: _lessonPayload(
              lesson: {
                'id': 'lesson-1',
                'course_id': 'course-1',
                'lesson_title': '',
                'position': 1,
                'content_document': _lessonDocument('Lesson'),
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

Map<String, Object?> _entryViewPayload({
  Object? course = _defaultEntryCourse,
  List<Object?> lessons = const [_defaultEntryLesson],
  Object? pricing = _defaultEntryPricing,
  Object? nextRecommendedLesson = _defaultEntryNextLesson,
  Map<String, Object?> cta = _defaultEntryCta,
}) {
  return {
    'course': course,
    'lessons': lessons,
    'access': const {
      'is_enrolled': true,
      'is_in_drip': true,
      'is_in_any_intro_drip': false,
      'can_enroll': false,
      'can_purchase': false,
    },
    'cta': cta,
    'pricing': pricing,
    'next_recommended_lesson': nextRecommendedLesson,
  };
}

const Map<String, Object?> _defaultEntryCourse = {
  'id': 'course-1',
  'slug': 'aveli-course',
  'title': 'Aveli 101',
  'description': 'Backend-authored course description',
  'cover': {
    'url': '/api/files/public-media/course-cover.png',
    'alt': 'Course cover',
  },
  'required_enrollment_source': 'purchase',
  'is_premium': true,
  'price_amount_cents': 99000,
  'price_currency': 'sek',
  'formatted_price': '990 kr',
  'sellable': true,
};

const Map<String, Object?> _defaultEntryLesson = {
  'id': 'lesson-1',
  'lesson_title': 'Start here',
  'position': 1,
  'availability': {
    'state': 'unlocked',
    'can_open': true,
    'reason_code': null,
    'reason_text': null,
    'next_unlock_at': null,
  },
  'progression': {
    'state': 'current',
    'completed_at': null,
    'is_next_recommended': true,
  },
};

const Map<String, Object?> _defaultEntryPricing = {
  'price_amount_cents': 99000,
  'price_currency': 'sek',
  'formatted_price': '990 kr',
  'sellable': true,
};

const Map<String, Object?> _defaultEntryCta = {
  'type': 'continue',
  'label': 'Continue',
  'enabled': true,
  'reason_code': null,
  'reason_text': null,
  'price': _defaultEntryPricing,
  'action': {'type': 'lesson', 'lesson_id': 'lesson-1'},
};

const Map<String, Object?> _defaultEntryNextLesson = {
  'id': 'lesson-1',
  'lesson_title': 'Start here',
  'position': 1,
};

Map<String, Object?> _coursePayload({
  String slug = 'aveli-course',
  String title = 'Aveli 101',
  String? coverMediaId = 'media-1',
  Object? cover = _defaultCover,
  int groupPosition = 0,
  int? priceCents = 0,
  String? requiredEnrollmentSource = 'intro',
  bool enrollable = true,
  bool purchasable = false,
  String? description = 'Backend-authored summary description',
  Map<String, Object?> extra = const {},
}) {
  return {
    'id': 'course-1',
    'slug': slug,
    'title': title,
    'description': description,
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
  bool isIntroCourse = false,
  bool selectionLocked = false,
  bool canAccess = true,
  String? nextUnlockAt,
  Map<String, Object?> extra = const {},
}) {
  return {
    'course_id': courseId,
    'group_position': 0,
    'required_enrollment_source': requiredEnrollmentSource,
    'enrollable': enrollable,
    'purchasable': purchasable,
    'is_intro_course': isIntroCourse,
    'selection_locked': selectionLocked,
    'can_access': canAccess,
    'next_unlock_at': nextUnlockAt,
    'enrollment': enrollment,
    ...extra,
  };
}

Map<String, Object?> _introSelectionPayload({
  bool selectionLocked = false,
  String? selectionLockReason,
  List<Map<String, Object?>> eligibleCourses = const [_defaultCoursePayload],
}) {
  return {
    'selection_locked': selectionLocked,
    'selection_lock_reason': selectionLockReason,
    'eligible_courses': eligibleCourses,
  };
}

const Map<String, Object?> _defaultCoursePayload = {
  'id': 'course-1',
  'slug': 'aveli-course',
  'title': 'Aveli 101',
  'description': 'Backend-authored summary description',
  'teacher': {'user_id': 'teacher-1', 'display_name': 'Aveli Teacher'},
  'group_position': 0,
  'course_group_id': 'group-1',
  'cover_media_id': 'media-1',
  'cover': _defaultCover,
  'price_amount_cents': 0,
  'drip_enabled': false,
  'drip_interval_days': null,
  'required_enrollment_source': 'intro',
  'enrollable': true,
  'purchasable': false,
};

const Map<String, Object?> _defaultEnrollment = {
  'id': 'enrollment-1',
  'user_id': 'user-1',
  'course_id': 'course-1',
  'source': 'purchase',
  'granted_at': '2024-01-10T12:00:00Z',
  'drip_started_at': '2024-01-10T12:00:00Z',
  'current_unlock_position': 1,
};

Map<String, Object?> _enrollmentPayload({String source = 'purchase'}) {
  return {
    'id': 'enrollment-1',
    'user_id': 'user-1',
    'course_id': 'course-1',
    'source': source,
    'granted_at': '2024-01-10T12:00:00Z',
    'drip_started_at': '2024-01-10T12:00:00Z',
    'current_unlock_position': 1,
  };
}

Map<String, Object?> _lessonPayload({
  Object? lesson,
  Object? media = const [],
}) {
  return {
    'lesson':
        lesson ??
        {
          'id': 'lesson-1',
          'course_id': 'course-1',
          'lesson_title': 'Lesson',
          'position': 1,
          'content_document': _lessonDocument(),
        },
    'navigation': const {'previous_lesson_id': null, 'next_lesson_id': null},
    'access': const {
      'has_access': true,
      'is_enrolled': true,
      'is_in_drip': false,
      'is_premium': false,
      'can_enroll': false,
      'can_purchase': false,
    },
    'cta': null,
    'pricing': null,
    'progression': const {'unlocked': true, 'reason': 'available'},
    'media': media,
  };
}

Map<String, Object?> _lessonDocument([String? text]) {
  return {
    'schema_version': 'lesson_document_v1',
    'blocks': text == null
        ? const []
        : [
            {
              'type': 'paragraph',
              'children': [
                {'text': text},
              ],
            },
          ],
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
