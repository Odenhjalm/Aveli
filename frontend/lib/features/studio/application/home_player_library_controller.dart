import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';

import 'studio_providers.dart';

class HomePlayerLibraryState extends Equatable {
  const HomePlayerLibraryState({
    required this.uploads,
    required this.courseLinks,
    required this.courseMedia,
  });

  factory HomePlayerLibraryState.fromPayload(HomePlayerLibraryPayload payload) {
    return HomePlayerLibraryState(
      uploads: _sortedUploads(payload.uploads),
      courseLinks: _sortedCourseLinks(payload.courseLinks),
      courseMedia: _sortedCourseMedia(payload.courseMedia),
    );
  }

  static const empty = HomePlayerLibraryState(
    uploads: [],
    courseLinks: [],
    courseMedia: [],
  );

  final List<HomePlayerUploadItem> uploads;
  final List<HomePlayerCourseLinkItem> courseLinks;
  final List<TeacherProfileLessonSource> courseMedia;

  @override
  List<Object?> get props => [uploads, courseLinks, courseMedia];

  static List<HomePlayerUploadItem> _sortedUploads(
    List<HomePlayerUploadItem> items,
  ) {
    final copy = List<HomePlayerUploadItem>.from(items);
    copy.sort((a, b) {
      final aDate = a.createdAt;
      final bDate = b.createdAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return copy;
  }

  static List<HomePlayerCourseLinkItem> _sortedCourseLinks(
    List<HomePlayerCourseLinkItem> items,
  ) {
    final copy = List<HomePlayerCourseLinkItem>.from(items);
    copy.sort((a, b) {
      final aDate = a.createdAt;
      final bDate = b.createdAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return copy;
  }

  static List<TeacherProfileLessonSource> _sortedCourseMedia(
    List<TeacherProfileLessonSource> sources,
  ) {
    final copy = List<TeacherProfileLessonSource>.from(sources);
    copy.sort((a, b) {
      final aCourse = (a.courseTitle ?? '').toLowerCase();
      final bCourse = (b.courseTitle ?? '').toLowerCase();
      final courseDiff = aCourse.compareTo(bCourse);
      if (courseDiff != 0) return courseDiff;
      final aLesson = (a.lessonTitle ?? '').toLowerCase();
      final bLesson = (b.lessonTitle ?? '').toLowerCase();
      final lessonDiff = aLesson.compareTo(bLesson);
      if (lessonDiff != 0) return lessonDiff;
      return a.id.compareTo(b.id);
    });
    return copy;
  }
}

class HomePlayerLibraryController
    extends AutoDisposeAsyncNotifier<HomePlayerLibraryState> {
  StudioRepository get _repository => ref.read(studioRepositoryProvider);

  @override
  FutureOr<HomePlayerLibraryState> build() async {
    return _load();
  }

  Future<HomePlayerLibraryState> _load() async {
    try {
      final payload = await _repository.fetchHomePlayerLibrary();
      return HomePlayerLibraryState.fromPayload(payload);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final snapshot = await _load();
      state = AsyncData(snapshot);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
    }
  }

  Future<void> uploadHomeMedia({
    required Uint8List data,
    required String filename,
    required String contentType,
    required String title,
  }) async {
    state = const AsyncLoading();
    try {
      await _repository.uploadHomePlayerUpload(
        data: data,
        filename: filename,
        contentType: contentType,
        title: title,
      );
      final snapshot = await _load();
      state = AsyncData(snapshot);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
      rethrow;
    }
  }

  Future<void> toggleUpload(String uploadId, bool active) async {
    state = const AsyncLoading();
    try {
      await _repository.updateHomePlayerUpload(
        uploadId,
        active: active,
      );
      final snapshot = await _load();
      state = AsyncData(snapshot);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
      rethrow;
    }
  }

  Future<void> deleteUpload(String uploadId) async {
    state = const AsyncLoading();
    try {
      await _repository.deleteHomePlayerUpload(uploadId);
      final snapshot = await _load();
      state = AsyncData(snapshot);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
      rethrow;
    }
  }

  Future<void> createCourseLink({
    required String lessonMediaId,
    required String title,
    bool enabled = true,
  }) async {
    state = const AsyncLoading();
    try {
      await _repository.createHomePlayerCourseLink(
        lessonMediaId: lessonMediaId,
        title: title,
        enabled: enabled,
      );
      final snapshot = await _load();
      state = AsyncData(snapshot);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
      rethrow;
    }
  }

  Future<void> toggleCourseLink(String linkId, bool enabled) async {
    state = const AsyncLoading();
    try {
      await _repository.updateHomePlayerCourseLink(linkId, enabled: enabled);
      final snapshot = await _load();
      state = AsyncData(snapshot);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
      rethrow;
    }
  }

  Future<void> deleteCourseLink(String linkId) async {
    state = const AsyncLoading();
    try {
      await _repository.deleteHomePlayerCourseLink(linkId);
      final snapshot = await _load();
      state = AsyncData(snapshot);
    } catch (error, stackTrace) {
      state = AsyncError(AppFailure.from(error, stackTrace), stackTrace);
      rethrow;
    }
  }
}

final homePlayerLibraryProvider =
    AutoDisposeAsyncNotifierProvider<HomePlayerLibraryController, HomePlayerLibraryState>(
      HomePlayerLibraryController.new,
    );

