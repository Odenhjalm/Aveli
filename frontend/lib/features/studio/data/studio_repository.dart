import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';

class StudioRepository {
  StudioRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<StudioStatus> fetchStatus() async {
    final res = await _client.get<Map<String, dynamic>>('/studio/status');
    return StudioStatus.fromJson(res);
  }

  Future<List<Map<String, dynamic>>> myCourses() async {
    final res = await _client.get<Map<String, dynamic>>('/studio/courses');
    final list = res['items'] as List? ?? const [];
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createCourse({
    required String title,
    required String slug,
    String? description,
    int? priceCents,
    bool isFreeIntro = false,
    bool isPublished = false,
    String? videoUrl,
    String? branch,
  }) async {
    final body = {
      'title': title,
      'slug': slug,
      if (description != null) 'description': description,
      if (priceCents != null) 'price_amount_cents': priceCents,
      'is_free_intro': isFreeIntro,
      'is_published': isPublished,
      if (videoUrl != null) 'video_url': videoUrl,
      if (branch != null) 'branch': branch,
    };
    final res = await _client.post<Map<String, dynamic>>(
      '/studio/courses',
      body: body,
    );
    return Map<String, dynamic>.from(res);
  }

  Future<Map<String, dynamic>?> fetchCourseMeta(String courseId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/studio/courses/$courseId',
    );
    return Map<String, dynamic>.from(res);
  }

  Future<Map<String, dynamic>> updateCourse(
    String courseId,
    Map<String, dynamic> patch,
  ) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/studio/courses/$courseId',
      body: patch,
    );
    return Map<String, dynamic>.from(res!);
  }

  Future<void> deleteCourse(String courseId) async {
    await _client.delete('/studio/courses/$courseId');
  }

  Future<List<Map<String, dynamic>>> listCourseLessons(String courseId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/studio/courses/$courseId/lessons',
    );
    final list = res['items'] as List? ?? const [];
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> upsertLesson({
    String? id,
    String? createId,
    required String courseId,
    required String title,
    String? contentMarkdown,
    int position = 0,
    bool isIntro = false,
  }) async {
    if (id == null) {
      final body = {
        'course_id': courseId,
        'title': title,
        'content_markdown': contentMarkdown,
        'position': position,
        'is_intro': isIntro,
        if (createId != null && createId.isNotEmpty) 'id': createId,
      };
      final res = await _client.post<Map<String, dynamic>>(
        '/studio/lessons',
        body: body,
      );
      return Map<String, dynamic>.from(res);
    } else {
      final body = <String, dynamic>{
        'title': title,
        if (contentMarkdown != null) 'content_markdown': contentMarkdown,
        'position': position,
        'is_intro': isIntro,
      };
      final res = await _client.patch<Map<String, dynamic>>(
        '/studio/lessons/$id',
        body: body,
      );
      return Map<String, dynamic>.from(res!);
    }
  }

  Future<void> deleteLesson(String lessonId) async {
    await _client.delete('/studio/lessons/$lessonId');
  }

  Future<void> updateLessonIntro({
    required String lessonId,
    required bool isIntro,
  }) async {
    await _client.patch(
      '/studio/lessons/$lessonId/intro',
      body: {'is_intro': isIntro},
    );
  }

  Future<List<Map<String, dynamic>>> listLessonMedia(String lessonId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/studio/lessons/$lessonId/media',
    );
    final list = res['items'] as List? ?? const [];
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> uploadLessonMedia({
    required String courseId,
    required String lessonId,
    required Uint8List data,
    required String filename,
    required String contentType,
    required bool isIntro,
    void Function(UploadProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (_isWavUpload(contentType, filename)) {
      return _uploadLessonWavViaPipeline(
        courseId: courseId,
        lessonId: lessonId,
        data: data,
        filename: filename,
        contentType: _normalizeWavMimeType(contentType, filename),
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }
    final fields = <String, dynamic>{
      'lesson_id': lessonId,
      'file': MultipartFile.fromBytes(
        data,
        filename: filename,
        contentType: MediaType.parse(contentType),
      ),
    };
    if (courseId.isNotEmpty) {
      fields['course_id'] = courseId;
    }
    final mediaType = _detectUploadMediaType(contentType);
    if (mediaType != null) {
      fields['type'] = mediaType;
    }
    if (isIntro) {
      fields['is_intro'] = isIntro;
    }

    final res = await _client.postForm<Map<String, dynamic>>(
      '/api/upload/course-media',
      FormData.fromMap(fields),
      onSendProgress: onProgress == null
          ? null
          : (sent, total) {
              if (total <= 0) return;
              onProgress(UploadProgress(sent: sent, total: total));
            },
      cancelToken: cancelToken,
    );
    final payload = res ?? const {};
    final media = payload['media'];
    if (media is Map<String, dynamic>) {
      return Map<String, dynamic>.from(media);
    }
    return Map<String, dynamic>.from(payload);
  }

  Future<Map<String, dynamic>> _uploadLessonWavViaPipeline({
    required String courseId,
    required String lessonId,
    required Uint8List data,
    required String filename,
    required String contentType,
    void Function(UploadProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final payload = <String, dynamic>{
      'filename': filename,
      'mime_type': contentType,
      'size_bytes': data.length,
      'media_type': 'audio',
      if (courseId.isNotEmpty) 'course_id': courseId,
      'lesson_id': lessonId,
    };

    final response = await _client.post<Map<String, dynamic>>(
      ApiPaths.mediaUploadUrl,
      body: payload,
    );

    final uploadUrlRaw = response['upload_url'] as String?;
    if (uploadUrlRaw == null || uploadUrlRaw.isEmpty) {
      throw StateError('Uppladdningslänk saknas för WAV.');
    }
    final headersRaw = response['headers'] as Map? ?? const {};
    final uploadHeaders = <String, String>{
      for (final entry in headersRaw.entries)
        entry.key.toString(): entry.value.toString(),
    };

    final dio = Dio();
    await dio.putUri<void>(
      Uri.parse(uploadUrlRaw),
      data: data,
      options: Options(headers: uploadHeaders),
      cancelToken: cancelToken,
      onSendProgress: (sent, total) {
        if (onProgress == null) return;
        final resolvedTotal = total > 0 ? total : data.length;
        onProgress(UploadProgress(sent: sent, total: resolvedTotal));
      },
    );

    return {
      'media_asset_id': response['media_id']?.toString(),
      'media_state': 'uploaded',
      'ingest_format': 'wav',
      'original_name': filename,
      'content_type': contentType,
    };
  }

  Future<void> deleteLessonMedia(String mediaId) async {
    await _client.delete('/studio/media/$mediaId');
  }

  Future<TeacherProfileMediaPayload> fetchProfileMedia() async {
    final res = await _client.get<Map<String, dynamic>>(
      '/studio/profile/media',
    );
    return TeacherProfileMediaPayload.fromJson(res);
  }

  Future<HomePlayerLibraryPayload> fetchHomePlayerLibrary() async {
    final res = await _client.get<Map<String, dynamic>>(
      '/studio/home-player/library',
    );
    return HomePlayerLibraryPayload.fromJson(res);
  }

  Future<HomePlayerUploadItem> uploadHomePlayerUpload({
    required Uint8List data,
    required String filename,
    required String contentType,
    required String title,
    bool active = true,
    void Function(UploadProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // Auth precheck is required for multipart uploads: `FormData` is single-use
    // (stream-backed) and cannot be safely retried after a 401 refresh flow.
    // Ensure the access token is valid and not near expiry *before* building
    // the `FormData` and starting the upload.
    final authed = await _client.ensureAuth(
      leeway: const Duration(minutes: 2),
    );
    if (!authed) {
      throw UnauthorizedFailure(
        message: 'Behörighet saknas. Logga in igen.',
      );
    }

    final fields = <String, dynamic>{
      'title': title,
      'active': active,
      'file': MultipartFile.fromBytes(
        data,
        filename: filename,
        contentType: MediaType.parse(contentType),
      ),
    };
    final res = await _client.postForm<Map<String, dynamic>>(
      '/studio/home-player/uploads',
      FormData.fromMap(fields),
      onSendProgress: onProgress == null
          ? null
          : (sent, total) {
              if (total <= 0) return;
              onProgress(UploadProgress(sent: sent, total: total));
            },
      cancelToken: cancelToken,
    );
    return HomePlayerUploadItem.fromJson(res ?? const {});
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
    String? mediaId,
    String? externalUrl,
    String? title,
    String? description,
    String? coverMediaId,
    String? coverImageUrl,
    int? position,
    bool? isPublished,
    Map<String, dynamic>? metadata,
  }) async {
    final body = <String, dynamic>{
      'media_kind': mediaKind.apiValue,
      if (mediaId != null) 'media_id': mediaId,
      if (externalUrl != null) 'external_url': externalUrl,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (coverMediaId != null) 'cover_media_id': coverMediaId,
      if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
      if (position != null) 'position': position,
      if (isPublished != null) 'is_published': isPublished,
      if (metadata != null) 'metadata': metadata,
    };
    final res = await _client.post<Map<String, dynamic>>(
      '/studio/profile/media',
      body: body,
    );
    return TeacherProfileMediaItem.fromJson(res);
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
    Map<String, dynamic>? metadata,
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
      if (metadata != null) 'metadata': metadata,
    };
    final res = await _client.patch<Map<String, dynamic>>(
      '/studio/profile/media/$itemId',
      body: body,
    );
    return TeacherProfileMediaItem.fromJson(res!);
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
      body: {'media_ids': orderedMediaIds},
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

bool _isWavUpload(String contentType, String filename) {
  final lower = contentType.toLowerCase();
  if (lower == 'audio/wav' ||
      lower == 'audio/x-wav' ||
      lower == 'audio/wave' ||
      lower == 'audio/vnd.wave') {
    return true;
  }
  return filename.toLowerCase().endsWith('.wav');
}

String _normalizeWavMimeType(String contentType, String filename) {
  final lower = contentType.toLowerCase();
  if (lower == 'audio/wav' || lower == 'audio/x-wav') {
    return lower;
  }
  if (lower == 'audio/wave' || lower == 'audio/vnd.wave') {
    return 'audio/wav';
  }
  if (filename.toLowerCase().endsWith('.wav')) {
    return 'audio/wav';
  }
  return lower.isEmpty ? 'audio/wav' : lower;
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
