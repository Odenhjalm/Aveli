import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';

final coursesRepositoryProvider = Provider<CoursesRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return CoursesRepository(client: client);
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

final introSelectionStateProvider =
    AutoDisposeFutureProvider<IntroSelectionStateData>((ref) async {
      final repo = ref.watch(coursesRepositoryProvider);
      return repo.fetchIntroSelectionState();
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

final courseStateProvider =
    AutoDisposeFutureProvider.family<CourseAccessData?, String>((
      ref,
      courseId,
    ) async {
      final auth = ref.watch(authControllerProvider);
      if (!auth.isAuthenticated) {
        return null;
      }
      final repo = ref.watch(coursesRepositoryProvider);
      return repo.fetchCourseState(courseId);
    });

final lessonDetailProvider =
    AutoDisposeFutureProvider.family<LessonDetailData, String>((
      ref,
      lessonId,
    ) async {
      final repo = ref.watch(coursesRepositoryProvider);
      return repo.fetchLessonDetail(lessonId);
    });

class EnrollController
    extends AutoDisposeFamilyAsyncNotifier<CourseAccessData?, String> {
  late final String _courseId;

  @override
  FutureOr<CourseAccessData?> build(String courseId) {
    _courseId = courseId;
    return null;
  }

  Future<void> enroll() async {
    final repo = ref.read(coursesRepositoryProvider);
    state = const AsyncLoading();
    try {
      final courseState = await repo.enrollCourse(_courseId);
      state = AsyncData(courseState);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
    }
  }
}

final enrollProvider =
    AutoDisposeAsyncNotifierProviderFamily<
      EnrollController,
      CourseAccessData?,
      String
    >(EnrollController.new);
