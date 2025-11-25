import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:wisdom/api/api_client.dart';
import 'package:wisdom/core/errors/app_failure.dart';
import 'package:wisdom/features/courses/data/course_access_api.dart';
import 'package:wisdom/features/courses/data/courses_repository.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _FakeAccessApi implements CourseAccessApi {
  const _FakeAccessApi({
    this.primary = false,
    this.fallback = false,
    this.throwPrimary = false,
    this.throwFallback = false,
  });

  final bool primary;
  final bool fallback;
  final bool throwPrimary;
  final bool throwFallback;

  @override
  Future<bool> fallbackHasAccess(String courseId) async {
    if (throwFallback) throw Exception('fallback');
    return fallback;
  }

  @override
  Future<bool> hasAccess(String courseId) async {
    if (throwPrimary) throw Exception('primary');
    return primary;
  }
}

void main() {
  group('CoursesRepository.hasAccess', () {
    late _MockApiClient client;

    setUp(() {
      client = _MockApiClient();
    });

    test('returns true when primary api grants access', () async {
      when(
        () => client.get<Map<String, dynamic>>('/courses/course-1/access'),
      ).thenAnswer(
        (_) async => {
          'has_access': true,
          'enrolled': true,
          'has_active_subscription': false,
          'free_consumed': 1,
          'free_limit': 3,
        },
      );

      final repo = CoursesRepository(client: client);

      final result = await repo.hasAccess('course-1');

      expect(result, isTrue);
    });

    test('falls back when primary throws', () async {
      when(
        () => client.get<Map<String, dynamic>>('/courses/course-2/access'),
      ).thenThrow(Exception('primary'));

      final repo = CoursesRepository(
        client: client,
        accessApi: const _FakeAccessApi(
          primary: false,
          fallback: true,
          throwPrimary: true,
        ),
      );

      final result = await repo.hasAccess('course-2');

      expect(result, isTrue);
    });

    test('returns false when both fail', () async {
      when(
        () => client.get<Map<String, dynamic>>('/courses/course-3/access'),
      ).thenThrow(Exception('primary'));

      final repo = CoursesRepository(
        client: client,
        accessApi: const _FakeAccessApi(
          primary: false,
          fallback: false,
          throwPrimary: true,
          throwFallback: true,
        ),
      );

      final result = await repo.hasAccess('course-3');

      expect(result, isFalse);
    });
  });

  group('CoursesRepository.fetchCourseDetailBySlug', () {
    const slug = 'wisdom-course';
    const courseId = 'course-1';

    test('enriches detail with enrollment, quota and order info', () async {
      final client = _MockApiClient();
      final repo = CoursesRepository(
        client: client,
        accessApi: const _FakeAccessApi(primary: true),
      );

      when(
        () => client.get<Map<String, dynamic>>(
          '/courses/by-slug/$slug',
          queryParameters: null,
        ),
      ).thenAnswer(
        (_) async => {
          'course': {
            'id': courseId,
            'slug': slug,
            'title': 'Aveli 101',
            'description': 'Intro description',
            'cover_url': null,
            'video_url': null,
            'is_free_intro': true,
            'is_published': true,
            'price_cents': 0,
          },
          'modules': [
            {
              'id': 'module-1',
              'course_id': courseId,
              'title': 'Module 1',
              'position': 1,
            },
          ],
          'lessons': {
            'module-1': [
              {
                'id': 'lesson-1',
                'module_id': 'module-1',
                'title': 'Welcome',
                'position': 1,
                'is_intro': true,
                'content_markdown': '# Intro',
              },
            ],
          },
        },
      );

      when(
        () => client.get<Map<String, dynamic>>(
          '/courses/$courseId/access',
          queryParameters: null,
        ),
      ).thenAnswer(
        (_) async => {
          'has_access': true,
          'enrolled': true,
          'has_active_subscription': false,
          'free_consumed': 2,
          'free_limit': 5,
          'latest_order': {
            'id': 'order-7',
            'status': 'paid',
            'amount_cents': 4500,
            'created_at': '2024-01-10T12:00:00Z',
          },
        },
      );

      final detail = await repo.fetchCourseDetailBySlug(slug);

      expect(detail.hasAccess, isTrue);
      expect(detail.isEnrolled, isTrue);
      expect(detail.freeConsumed, 2);
      expect(detail.freeLimit, 5);
      expect(detail.latestOrder, isNotNull);
      expect(detail.latestOrder!.id, 'order-7');
      expect(detail.modules, isNotEmpty);
      expect(detail.lessonsByModule['module-1'], isNotEmpty);
    });

    test('handles unauthorized quota and missing order gracefully', () async {
      final client = _MockApiClient();
      final repo = CoursesRepository(
        client: client,
        accessApi: const _FakeAccessApi(primary: false),
      );

      when(
        () => client.get<Map<String, dynamic>>(
          '/courses/by-slug/$slug',
          queryParameters: null,
        ),
      ).thenAnswer(
        (_) async => {
          'course': {
            'id': courseId,
            'slug': slug,
            'title': 'Aveli 101',
            'description': null,
            'cover_url': null,
            'video_url': null,
            'is_free_intro': false,
            'is_published': true,
            'price_cents': 1500,
          },
          'modules': [],
          'lessons': {},
        },
      );

      when(
        () => client.get<Map<String, dynamic>>(
          '/courses/$courseId/access',
          queryParameters: null,
        ),
      ).thenThrow(UnauthorizedFailure(message: 'not allowed'));

      final detail = await repo.fetchCourseDetailBySlug(slug);

      expect(detail.hasAccess, isFalse);
      expect(detail.isEnrolled, isFalse);
      expect(detail.freeConsumed, 0);
      expect(detail.freeLimit, 0);
      expect(detail.latestOrder, isNull);
    });
  });
}
