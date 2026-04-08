import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';

import 'studio_models.dart';

part 'studio_repository_lesson_media.dart';

class StudioRepository {
  StudioRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  _StudioLessonMediaScope get _lessonMedia => _StudioLessonMediaScope(_client);

  Future<T> _unsupportedRuntime<T>(String surface) {
    return Future<T>.error(
      UnsupportedError('$surface is inert in mounted runtime'),
    );
  }

  static Object? _requiredResponseField(
    Object? payload,
    String field,
    String label,
  ) {
    switch (payload) {
      case final Map data when data.containsKey(field):
        return data[field];
      case final Map _:
        throw StateError('$label is missing required field: $field');
      default:
        throw StateError('$label returned a non-object payload');
    }
  }

  static List<Object?> _requiredResponseListField(
    Object? payload,
    String field,
    String label,
  ) {
    final value = _requiredResponseField(payload, field, label);
    if (value is List) {
      return List<Object?>.from(value);
    }
    throw StateError('$label field "$field" must be a list');
  }

  Future<StudioStatus> fetchStatus() async {
    return _unsupportedRuntime('Studio status');
  }

  Future<Map<String, Object?>> createReferralInvitation({
    required String email,
    int? freeDays,
    int? freeMonths,
  }) async {
    return _unsupportedRuntime('Studio referrals');
  }

  Future<List<CourseStudio>> myCourses() async {
    final response = await _client.raw.get<Object?>('/studio/courses');
    final items = _requiredResponseListField(
      response.data,
      'items',
      'Studio course list',
    );
    return items
        .map(
          (item) =>
              CourseStudio.fromResponse(item, label: 'Studio course list item'),
        )
        .toList(growable: false);
  }

  Future<CourseStudio> createCourse({
    required String title,
    required String slug,
  }) async {
    return _unsupportedRuntime('Studio course creation');
  }

  Future<CourseStudio> fetchCourseMeta(String courseId) async {
    final response = await _client.raw.get<Object?>(
      '/studio/courses/$courseId',
    );
    return CourseStudio.fromResponse(response.data, label: 'Studio course');
  }

  Future<CourseStudio> updateCourse(
    String courseId,
    Map<String, Object?> patch,
  ) async {
    final response = await _client.raw.patch<Object?>(
      '/studio/courses/$courseId',
      data: patch,
    );
    return CourseStudio.fromResponse(
      response.data,
      label: 'Updated studio course',
    );
  }

  Future<void> deleteCourse(String courseId) async {
    await _client.delete('/studio/courses/$courseId');
  }

  Future<List<LessonStudio>> listCourseLessons(String courseId) async {
    final response = await _client.raw.get<Object?>(
      '/studio/courses/$courseId/lessons',
    );
    final items = _requiredResponseListField(
      response.data,
      'items',
      'Studio lesson list',
    );
    return items
        .map(
          (item) =>
              LessonStudio.fromResponse(item, label: 'Studio lesson list item'),
        )
        .toList(growable: false);
  }

  Future<LessonStudio> upsertLesson({
    String? id,
    String? createId,
    required String courseId,
    required String lessonTitle,
    required String contentMarkdown,
    int position = 0,
  }) async {
    if (id == null) {
      final body = <String, Object?>{
        'course_id': courseId,
        'lesson_title': lessonTitle,
        'content_markdown': contentMarkdown,
        'position': position,
        if (createId != null && createId.isNotEmpty) 'id': createId,
      };
      final response = await _client.raw.post<Object?>(
        '/studio/lessons',
        data: body,
      );
      return LessonStudio.fromResponse(
        response.data,
        label: 'Created studio lesson',
      );
    } else {
      final body = <String, Object?>{
        'lesson_title': lessonTitle,
        'content_markdown': contentMarkdown,
        'position': position,
      };
      final response = await _client.raw.patch<Object?>(
        '/studio/lessons/$id',
        data: body,
      );
      return LessonStudio.fromResponse(
        response.data,
        label: 'Updated studio lesson',
      );
    }
  }

  Future<void> deleteLesson(String lessonId) async {
    await _client.delete('/studio/lessons/$lessonId');
  }

  Future<List<StudioLessonMediaItem>> listLessonMedia(String lessonId) =>
      _lessonMedia.listLessonMedia(lessonId);

  Future<StudioLessonMediaPreviewBatch> fetchLessonMediaPreviews(
    List<String> lessonMediaIds,
  ) => _lessonMedia.fetchLessonMediaPreviews(lessonMediaIds);

  Future<StudioLessonMediaItem> uploadLessonMedia({
    required String lessonId,
    required Uint8List data,
    required String filename,
    required String contentType,
    required String mediaType,
    void Function(UploadProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) => _lessonMedia.uploadLessonMedia(
    lessonId: lessonId,
    data: data,
    filename: filename,
    contentType: contentType,
    mediaType: mediaType,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );

  Future<void> deleteLessonMedia(String lessonId, String lessonMediaId) =>
      _lessonMedia.deleteLessonMedia(lessonId, lessonMediaId);

  Future<TeacherProfileMediaPayload> fetchProfileMedia() async {
    return _unsupportedRuntime('Studio profile media');
  }

  Future<HomePlayerLibraryPayload> fetchHomePlayerLibrary() async {
    return _unsupportedRuntime('Home player library');
  }

  Future<HomePlayerUploadItem> uploadHomePlayerUpload({
    required String title,
    required String mediaAssetId,
    bool active = true,
  }) async {
    return _unsupportedRuntime('Home player uploads');
  }

  Future<Map<String, Object?>> requestHomePlayerUploadUrl({
    required String filename,
    required String mimeType,
    required int sizeBytes,
  }) async {
    return _unsupportedRuntime('Home player upload URLs');
  }

  Future<Map<String, Object?>> refreshHomePlayerUploadUrl({
    required String objectPath,
    required String mimeType,
  }) async {
    return _unsupportedRuntime('Home player upload URL refresh');
  }

  Future<HomePlayerUploadItem> createHomePlayerUploadFromStorage({
    required String title,
    required String storagePath,
    required String contentType,
    required int byteSize,
    required String originalName,
    bool active = true,
    String storageBucket = 'course-media',
  }) async {
    return _unsupportedRuntime('Home player storage uploads');
  }

  Future<HomePlayerUploadItem> updateHomePlayerUpload(
    String uploadId, {
    String? title,
    bool? active,
  }) async {
    return _unsupportedRuntime('Home player uploads');
  }

  Future<void> deleteHomePlayerUpload(String uploadId) async {
    return _unsupportedRuntime('Home player uploads');
  }

  Future<HomePlayerCourseLinkItem> createHomePlayerCourseLink({
    required String lessonMediaId,
    required String title,
    bool enabled = true,
  }) async {
    return _unsupportedRuntime('Home player course links');
  }

  Future<HomePlayerCourseLinkItem> updateHomePlayerCourseLink(
    String linkId, {
    bool? enabled,
    String? title,
  }) async {
    return _unsupportedRuntime('Home player course links');
  }

  Future<void> deleteHomePlayerCourseLink(String linkId) async {
    return _unsupportedRuntime('Home player course links');
  }

  Future<TeacherProfileMediaItem> createProfileMedia({
    required TeacherProfileMediaKind mediaKind,
    String? lessonMediaId,
    String? seminarRecordingId,
    String? externalUrl,
    String? title,
    String? description,
    String? coverMediaId,
    String? coverImageUrl,
    required int position,
    required bool isPublished,
    required bool enabledForHomePlayer,
  }) async {
    return _unsupportedRuntime('Studio profile media');
  }

  Future<TeacherProfileMediaItem> updateProfileMedia(
    String itemId, {
    String? title,
    String? description,
    String? coverMediaId,
    String? coverImageUrl,
    int? position,
    bool? isPublished,
    bool? enabledForHomePlayer,
  }) async {
    return _unsupportedRuntime('Studio profile media');
  }

  Future<void> deleteProfileMedia(String itemId) async {
    return _unsupportedRuntime('Studio profile media');
  }

  Future<void> reorderLessonMedia(
    String lessonId,
    List<String> orderedMediaIds,
  ) => _lessonMedia.reorderLessonMedia(lessonId, orderedMediaIds);

  Future<void> reorderCourseLessons(
    String courseId,
    List<Map<String, Object?>> orderedLessons,
  ) async {
    await _client.patch(
      '/studio/courses/$courseId/lessons/reorder',
      body: {'lessons': orderedLessons},
    );
  }

  Future<Uint8List> downloadMedia(String mediaId) async {
    return _unsupportedRuntime('Studio media download');
  }

  Future<Map<String, Object?>> ensureQuiz(String courseId) async {
    return _unsupportedRuntime('Studio quiz shell');
  }

  Future<List<Map<String, Object?>>> myCertificates({
    bool verifiedOnly = false,
  }) async {
    return _unsupportedRuntime('Studio certificates');
  }

  Future<Map<String, Object?>> addCertificate({
    required String title,
    String status = 'pending',
    String? notes,
    String? evidenceUrl,
  }) async {
    return _unsupportedRuntime('Studio certificates');
  }

  Future<List<Map<String, Object?>>> quizQuestions(String quizId) async {
    return _unsupportedRuntime('Studio quiz questions');
  }

  Future<Map<String, Object?>> upsertQuestion({
    required String quizId,
    String? id,
    required Map<String, Object?> data,
  }) async {
    return _unsupportedRuntime('Studio quiz questions');
  }

  Future<void> deleteQuestion(String quizId, String questionId) async {
    return _unsupportedRuntime('Studio quiz questions');
  }
}

class StudioStatus {
  const StudioStatus({
    required this.isTeacher,
    required this.verifiedCertificates,
    required this.hasApplication,
  });

  final bool isTeacher;
  final int verifiedCertificates;
  final bool hasApplication;

  factory StudioStatus.fromResponse(Object? payload) {
    final role = StudioRepository._requiredResponseField(
      payload,
      'role',
      'Studio status',
    );
    final isAdmin = StudioRepository._requiredResponseField(
      payload,
      'is_admin',
      'Studio status',
    );
    final verifiedCertificates = StudioRepository._requiredResponseField(
      payload,
      'verified_certificates',
      'Studio status',
    );
    final hasApplication = StudioRepository._requiredResponseField(
      payload,
      'has_application',
      'Studio status',
    );
    if (role is! String) {
      throw StateError('Studio status field "role" must be a string');
    }
    if (isAdmin is! bool) {
      throw StateError('Studio status field "is_admin" must be a bool');
    }
    if (verifiedCertificates is! int && verifiedCertificates is! num) {
      throw StateError(
        'Studio status field "verified_certificates" must be an int',
      );
    }
    if (hasApplication is! bool) {
      throw StateError('Studio status field "has_application" must be a bool');
    }
    return StudioStatus(
      isTeacher: role == 'teacher',
      verifiedCertificates: verifiedCertificates is int
          ? verifiedCertificates
          : (verifiedCertificates as num).toInt(),
      hasApplication: hasApplication,
    );
  }
}
