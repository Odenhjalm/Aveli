import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';

import 'studio_models.dart';

class StudioRepository {
  StudioRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<StudioStatus> fetchStatus() async {
    final res = await _client.get<Map<String, dynamic>>('/studio/status');
    return StudioStatus.fromJson(res);
  }

  Future<Map<String, dynamic>> createReferralInvitation({
    required String email,
    int? freeDays,
    int? freeMonths,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/studio/referrals/create',
      body: {
        'email': email,
        if (freeDays != null) 'free_days': freeDays,
        if (freeMonths != null) 'free_months': freeMonths,
      },
    );
    return Map<String, dynamic>.from(res);
  }

  Future<List<CourseStudio>> myCourses() async {
    final res = await _client.get<Map<String, dynamic>>('/studio/courses');
    final list = res['items'] as List? ?? const [];
    return list
        .map((e) => CourseStudio.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  }

  Future<StudioCourseDetails> createCourse({
    required String title,
    required String slug,
  }) async {
    final body = {'title': title, 'slug': slug};
    final res = await _client.post<Map<String, dynamic>>(
      '/studio/courses',
      body: body,
    );
    return StudioCourseDetails.fromJson(res);
  }

  Future<StudioCourseDetails> fetchCourseMeta(String courseId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/studio/courses/$courseId',
    );
    return StudioCourseDetails.fromJson(res);
  }

  Future<StudioCourseDetails> updateCourse(
    String courseId,
    Map<String, dynamic> patch,
  ) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/studio/courses/$courseId',
      body: patch,
    );
    return StudioCourseDetails.fromJson(res!);
  }

  Future<void> deleteCourse(String courseId) async {
    await _client.delete('/studio/courses/$courseId');
  }

  Future<List<LessonStudio>> listCourseLessons(String courseId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/studio/courses/$courseId/lessons',
    );
    final list = res['items'] as List? ?? const [];
    return list
        .map((e) => LessonStudio.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  }

  Future<LessonStudio> upsertLesson({
    String? id,
    String? createId,
    required String courseId,
    required String lessonTitle,
    String? contentMarkdown,
    int position = 0,
  }) async {
    if (id == null) {
      final body = {
        'course_id': courseId,
        'lesson_title': lessonTitle,
        'content_markdown': contentMarkdown,
        'position': position,
        if (createId != null && createId.isNotEmpty) 'id': createId,
      };
      final res = await _client.post<Map<String, dynamic>>(
        '/studio/lessons',
        body: body,
      );
      return LessonStudio.fromJson(res);
    } else {
      final body = <String, dynamic>{
        'lesson_title': lessonTitle,
        if (contentMarkdown != null) 'content_markdown': contentMarkdown,
        'position': position,
      };
      final res = await _client.patch<Map<String, dynamic>>(
        '/studio/lessons/$id',
        body: body,
      );
      return LessonStudio.fromJson(res!);
    }
  }

  Future<void> deleteLesson(String lessonId) async {
    await _client.delete('/studio/lessons/$lessonId');
  }

  Future<List<StudioLessonMediaItem>> listLessonMedia(String lessonId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/studio/lessons/$lessonId/media',
    );
    final list = res['items'] as List? ?? const [];
    return list
        .map(
          (e) => StudioLessonMediaItem.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, StudioLessonMediaPreviewItem>> fetchLessonMediaPreviews(
    List<String> lessonMediaIds,
  ) async {
    final normalizedIds = lessonMediaIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedIds.isEmpty) {
      return const <String, StudioLessonMediaPreviewItem>{};
    }

    final res = await _client.post<Map<String, dynamic>>(
      ApiPaths.mediaPreviews,
      body: {'ids': normalizedIds},
    );
    final rawItems = res['items'] is Map ? res['items'] as Map : res;
    final items = <String, StudioLessonMediaPreviewItem>{};
    rawItems.forEach((key, value) {
      if (value is! Map) return;
      items[key.toString()] = StudioLessonMediaPreviewItem.fromJson(
        key.toString(),
        Map<String, dynamic>.from(value),
      );
    });
    return items;
  }

  Future<StudioLessonMediaItem> uploadLessonMedia({
    required String lessonId,
    required Uint8List data,
    required String filename,
    required String contentType,
    void Function(UploadProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final mediaType = _detectUploadMediaType(contentType);
    if (mediaType == null) {
      throw StateError(
        'Unsupported lesson media content type for canonical edge contract.',
      );
    }

    final upload = await _requestLessonMediaUploadTarget(
      filename: filename,
      mimeType: contentType,
      sizeBytes: data.length,
      mediaType: mediaType,
      lessonId: lessonId,
    );
    if (upload.uploadUrl.trim().isEmpty) {
      throw StateError('Ofullständigt svar från studio media upload-url.');
    }

    final dio = Dio();
    await dio.putUri<void>(
      Uri.parse(upload.uploadUrl),
      data: data,
      options: Options(headers: upload.headers),
      cancelToken: cancelToken,
      onSendProgress: (sent, total) {
        if (onProgress == null) return;
        final resolvedTotal = total > 0 ? total : data.length;
        onProgress(UploadProgress(sent: sent, total: resolvedTotal));
      },
    );

    final res = await _client.post<Map<String, dynamic>>(
      '/studio/lessons/$lessonId/media/${upload.lessonMediaId}/complete',
      body: const <String, dynamic>{},
    );
    return StudioLessonMediaItem.fromJson(res);
  }

  Future<StudioLessonMediaUploadTarget> _requestLessonMediaUploadTarget({
    required String filename,
    required String mimeType,
    required int sizeBytes,
    required String mediaType,
    required String lessonId,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/studio/lessons/$lessonId/media/upload-url',
      body: <String, dynamic>{
        'filename': filename,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        'media_type': mediaType,
      },
    );
    return StudioLessonMediaUploadTarget.fromJson(res);
  }

  Future<void> deleteLessonMedia(String lessonId, String lessonMediaId) async {
    await _client.delete('/studio/lessons/$lessonId/media/$lessonMediaId');
  }

  Future<TeacherProfileMediaPayload> fetchProfileMedia() async {
    final response = await _client.raw.get<Object?>('/studio/profile/media');
    return TeacherProfileMediaPayload.fromResponse(response.data);
  }

  Future<HomePlayerLibraryPayload> fetchHomePlayerLibrary() async {
    final res = await _client.get<Map<String, dynamic>>(
      '/studio/home-player/library',
    );
    return HomePlayerLibraryPayload.fromJson(res);
  }

  Future<HomePlayerUploadItem> uploadHomePlayerUpload({
    required String title,
    required String mediaAssetId,
    bool active = true,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      'active': active,
      'media_asset_id': mediaAssetId,
    };
    final res = await _client.post<Map<String, dynamic>>(
      '/studio/home-player/uploads',
      body: body,
    );
    return HomePlayerUploadItem.fromJson(res);
  }

  Future<Map<String, dynamic>> requestHomePlayerUploadUrl({
    required String filename,
    required String mimeType,
    required int sizeBytes,
  }) async {
    final body = <String, dynamic>{
      'filename': filename,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
    };
    final res = await _client.post<Map<String, dynamic>>(
      '/studio/home-player/uploads/upload-url',
      body: body,
    );
    return Map<String, dynamic>.from(res);
  }

  Future<Map<String, dynamic>> refreshHomePlayerUploadUrl({
    required String objectPath,
    required String mimeType,
  }) async {
    final body = <String, dynamic>{
      'object_path': objectPath,
      'mime_type': mimeType,
    };
    final res = await _client.post<Map<String, dynamic>>(
      '/studio/home-player/uploads/upload-url/refresh',
      body: body,
    );
    return Map<String, dynamic>.from(res);
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
    final body = <String, dynamic>{
      'title': title,
      'active': active,
      'storage_bucket': storageBucket,
      'storage_path': storagePath,
      'content_type': contentType,
      'byte_size': byteSize,
      'original_name': originalName,
    };
    final res = await _client.post<Map<String, dynamic>>(
      '/studio/home-player/uploads',
      body: body,
    );
    return HomePlayerUploadItem.fromJson(res);
  }

  Future<HomePlayerUploadItem> updateHomePlayerUpload(
    String uploadId, {
    String? title,
    bool? active,
  }) async {
    final body = <String, dynamic>{
      if (title != null) 'title': title,
      if (active != null) 'active': active,
    };
    final res = await _client.patch<Map<String, dynamic>>(
      '/studio/home-player/uploads/$uploadId',
      body: body,
    );
    return HomePlayerUploadItem.fromJson(res ?? const {});
  }

  Future<void> deleteHomePlayerUpload(String uploadId) async {
    await _client.delete('/studio/home-player/uploads/$uploadId');
  }

  Future<HomePlayerCourseLinkItem> createHomePlayerCourseLink({
    required String lessonMediaId,
    required String title,
    bool enabled = true,
  }) async {
    final body = <String, dynamic>{
      'lesson_media_id': lessonMediaId,
      'title': title,
      'enabled': enabled,
    };
    final res = await _client.post<Map<String, dynamic>>(
      '/studio/home-player/course-links',
      body: body,
    );
    return HomePlayerCourseLinkItem.fromJson(res);
  }

  Future<HomePlayerCourseLinkItem> updateHomePlayerCourseLink(
    String linkId, {
    bool? enabled,
    String? title,
  }) async {
    final body = <String, dynamic>{
      if (enabled != null) 'enabled': enabled,
      if (title != null) 'title': title,
    };
    final res = await _client.patch<Map<String, dynamic>>(
      '/studio/home-player/course-links/$linkId',
      body: body,
    );
    return HomePlayerCourseLinkItem.fromJson(res ?? const {});
  }

  Future<void> deleteHomePlayerCourseLink(String linkId) async {
    await _client.delete('/studio/home-player/course-links/$linkId');
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
    final body = <String, dynamic>{
      'media_kind': mediaKind.apiValue,
      if (lessonMediaId != null) 'lesson_media_id': lessonMediaId,
      if (seminarRecordingId != null)
        'seminar_recording_id': seminarRecordingId,
      if (externalUrl != null) 'external_url': externalUrl,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (coverMediaId != null) 'cover_media_id': coverMediaId,
      if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
      'position': position,
      'is_published': isPublished,
      'enabled_for_home_player': enabledForHomePlayer,
    };
    final res = await _client.post<Map<String, dynamic>>(
      '/studio/profile/media',
      body: body,
    );
    return TeacherProfileMediaItem.fromResponse(res);
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
    final body = <String, dynamic>{
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (coverMediaId != null) 'cover_media_id': coverMediaId,
      if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
      if (position != null) 'position': position,
      if (isPublished != null) 'is_published': isPublished,
      if (enabledForHomePlayer != null)
        'enabled_for_home_player': enabledForHomePlayer,
    };
    final res = await _client.patch<Map<String, dynamic>>(
      '/studio/profile/media/$itemId',
      body: body,
    );
    return TeacherProfileMediaItem.fromResponse(res);
  }

  Future<void> deleteProfileMedia(String itemId) async {
    await _client.delete('/studio/profile/media/$itemId');
  }

  Future<void> reorderLessonMedia(
    String lessonId,
    List<String> orderedMediaIds,
  ) async {
    await _client.patch(
      '/studio/lessons/$lessonId/media/reorder',
      body: {'lesson_media_ids': orderedMediaIds},
    );
  }

  Future<void> reorderCourseLessons(
    String courseId,
    List<Map<String, dynamic>> orderedLessons,
  ) async {
    await _client.patch(
      '/studio/courses/$courseId/lessons/reorder',
      body: {'lessons': orderedLessons},
    );
  }

  Future<Uint8List> downloadMedia(String mediaId) {
    return _client.getBytes('/studio/media/$mediaId');
  }

  Future<Map<String, dynamic>> ensureQuiz(String courseId) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/studio/courses/$courseId/quiz',
    );
    return Map<String, dynamic>.from(res['quiz'] as Map);
  }

  Future<List<Map<String, dynamic>>> myCertificates({
    bool verifiedOnly = false,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/studio/certificates',
      queryParameters: {'verified_only': verifiedOnly},
    );
    final list = res['items'] as List? ?? const [];
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> addCertificate({
    required String title,
    String status = 'pending',
    String? notes,
    String? evidenceUrl,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/studio/certificates',
      body: {
        'title': title,
        'status': status,
        if (notes != null) 'notes': notes,
        if (evidenceUrl != null) 'evidence_url': evidenceUrl,
      },
    );
    return Map<String, dynamic>.from(res);
  }

  Future<List<Map<String, dynamic>>> quizQuestions(String quizId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/studio/quizzes/$quizId/questions',
    );
    final list = res['items'] as List? ?? const [];
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> upsertQuestion({
    required String quizId,
    String? id,
    required Map<String, dynamic> data,
  }) async {
    final body = {...data}..remove('quiz_id');
    if (id == null) {
      final res = await _client.post<Map<String, dynamic>>(
        '/studio/quizzes/$quizId/questions',
        body: body,
      );
      return Map<String, dynamic>.from(res);
    } else {
      final res = await _client.put<Map<String, dynamic>>(
        '/studio/quizzes/$quizId/questions/$id',
        body: body,
      );
      return Map<String, dynamic>.from(res!);
    }
  }

  Future<void> deleteQuestion(String quizId, String questionId) async {
    await _client.delete('/studio/quizzes/$quizId/questions/$questionId');
  }
}

String? _detectUploadMediaType(String contentType) {
  if (contentType.isEmpty) return null;
  final lower = contentType.toLowerCase();
  if (lower.startsWith('image/')) return 'image';
  if (lower.startsWith('video/')) return 'video';
  if (lower.startsWith('audio/')) return 'audio';
  if (lower == 'application/pdf') return 'document';
  return null;
}

class UploadProgress {
  const UploadProgress({required this.sent, required this.total});

  final int sent;
  final int total;

  double get fraction => total == 0 ? 0 : sent / total;
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

  factory StudioStatus.fromJson(Map<String, dynamic> json) => StudioStatus(
    isTeacher: json['is_teacher'] == true,
    verifiedCertificates: (json['verified_certificates'] as num?)?.toInt() ?? 0,
    hasApplication: json['has_application'] == true,
  );
}
