import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/api/auth_repository.dart';
import 'package:wisdom/core/errors/app_failure.dart';
import 'package:wisdom/features/courses/data/courses_repository.dart';
import 'package:wisdom/features/courses/data/progress_repository.dart';

final coursesRepositoryProvider = Provider<CoursesRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return CoursesRepository(client: client);
});

final progressRepositoryProvider = Provider<ProgressRepository>((ref) {
  return ProgressRepository();
});

final coursesProvider = AutoDisposeFutureProvider<List<CourseSummary>>((
  ref,
) async {
  final repo = ref.watch(coursesRepositoryProvider);
  return repo.fetchPublishedCourses();
});

final myCoursesProvider = AutoDisposeFutureProvider<List<CourseSummary>>((
  ref,
) async {
  final repo = ref.watch(coursesRepositoryProvider);
  return repo.myEnrolledCourses();
});

final firstFreeIntroCourseProvider = AutoDisposeFutureProvider<CourseSummary?>((
  ref,
) async {
  final repo = ref.watch(coursesRepositoryProvider);
  return repo.firstFreeIntroCourse();
});

final courseDetailProvider =
    AutoDisposeFutureProvider.family<CourseDetailData, String>((
      ref,
      slug,
    ) async {
      final repo = ref.watch(coursesRepositoryProvider);
      return repo.fetchCourseDetailBySlug(slug);
    });

final courseByIdProvider =
    AutoDisposeFutureProvider.family<CourseSummary?, String>((
      ref,
      courseId,
    ) async {
      final repo = ref.watch(coursesRepositoryProvider);
      return repo.getCourseById(courseId);
    });

final hasCourseAccessProvider = AutoDisposeFutureProvider.family<bool, String>((
  ref,
  courseId,
) async {
  final repo = ref.watch(coursesRepositoryProvider);
  return repo.isEnrolled(courseId);
});

final lessonDetailProvider =
    AutoDisposeFutureProvider.family<LessonDetailData, String>((
      ref,
      lessonId,
    ) async {
      final repo = ref.watch(coursesRepositoryProvider);
      return repo.fetchLessonDetail(lessonId);
    });

final courseQuizInfoProvider =
    AutoDisposeFutureProvider.family<CourseQuizInfo, String>((
      ref,
      courseId,
    ) async {
      final repo = ref.watch(coursesRepositoryProvider);
      return repo.fetchQuizInfo(courseId);
    });

final quizQuestionsProvider =
    AutoDisposeFutureProvider.family<List<QuizQuestion>, String>((
      ref,
      quizId,
    ) async {
      final repo = ref.watch(coursesRepositoryProvider);
      return repo.fetchQuizQuestions(quizId);
    });

class CourseProgressRequest {
  CourseProgressRequest(List<String> ids)
    : courseIds = List.unmodifiable(ids..sort());

  final List<String> courseIds;

  @override
  bool operator ==(Object other) {
    return other is CourseProgressRequest &&
        _listEquals(other.courseIds, courseIds);
  }

  @override
  int get hashCode => Object.hashAll(courseIds);
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final courseProgressProvider =
    AutoDisposeFutureProvider.family<
      Map<String, double>,
      CourseProgressRequest
    >((ref, request) async {
      final repo = ref.watch(progressRepositoryProvider);
      return repo.getProgressForCourses(request.courseIds);
    });

class EnrollController extends AutoDisposeFamilyAsyncNotifier<void, String> {
  late final String _courseId;

  @override
  FutureOr<void> build(String courseId) {
    _courseId = courseId;
  }

  Future<void> enroll() async {
    final repo = ref.read(coursesRepositoryProvider);
    state = const AsyncLoading();
    try {
      await repo.enrollFreeIntro(_courseId);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
    }
  }
}

final enrollProvider =
    AutoDisposeAsyncNotifierProviderFamily<EnrollController, void, String>(
      EnrollController.new,
    );

class QuizSubmissionController
    extends AutoDisposeFamilyAsyncNotifier<Map<String, dynamic>?, String> {
  late final String _quizId;

  @override
  FutureOr<Map<String, dynamic>?> build(String quizId) {
    _quizId = quizId;
    return null;
  }

  Future<void> submit(Map<String, dynamic> answers) async {
    final repo = ref.read(coursesRepositoryProvider);
    state = const AsyncLoading();
    try {
      final result = await repo.submitQuiz(quizId: _quizId, answers: answers);
      state = AsyncData(result);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
    }
  }
}

final quizSubmissionProvider =
    AutoDisposeAsyncNotifierProviderFamily<
      QuizSubmissionController,
      Map<String, dynamic>?,
      String
    >(QuizSubmissionController.new);
