import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';
import 'package:aveli/editor/document/lesson_document.dart';

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

  static Map<String, Object?> _requiredResponseMap(
    Object? payload,
    String label,
  ) {
    switch (payload) {
      case final Map data:
        return Map<String, Object?>.from(data);
      default:
        throw StateError('$label returned a non-object payload');
    }
  }

  static String _requiredEtagHeader(Response<Object?> response, String label) {
    final etag = response.headers.value('etag')?.trim();
    if (etag == null || etag.isEmpty) {
      throw StateError('$label is missing required ETag header');
    }
    return etag;
  }

  static void _rejectCourseDripAuthoringPatch(Map<String, Object?> patch) {
    const forbiddenFields = <String>{
      'drip_enabled',
      'drip_interval_days',
      'drip_authoring',
      'legacy_uniform',
      'custom_schedule',
      'mode',
    };
    final forbidden = patch.keys
        .where(forbiddenFields.contains)
        .toList(growable: false);
    if (forbidden.isEmpty) {
      return;
    }
    throw UnsupportedError(
      'Use updateCourseDripAuthoring for drip schedule changes: ${forbidden.join(', ')}',
    );
  }

  static void _validateCourseDripAuthoringPayload(
    Map<String, Object?> payload,
  ) {
    const allowedFields = <String>{'mode', 'legacy_uniform', 'custom_schedule'};
    final unexpected = payload.keys.where(
      (key) => !allowedFields.contains(key),
    );
    if (unexpected.isNotEmpty) {
      throw UnsupportedError(
        'Course drip authoring payload contains unsupported fields: ${unexpected.join(', ')}',
      );
    }
  }

  Future<StudioStatus> fetchStatus() async {
    final response = await _client.raw.get<Object?>('/studio/status');
    return StudioStatus.fromResponse(response.data);
  }

  Future<SpecialOfferExecutionState?>
  fetchCurrentSpecialOfferExecutionState() async {
    try {
      final response = await _client.raw.get<Object?>(
        '/api/teachers/special-offers/execution/current',
      );
      return SpecialOfferExecutionState.fromResponse(
        response.data,
        label: 'Current special-offer execution state',
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<SpecialOfferExecutionState> createSpecialOfferExecution({
    required List<String> courseIds,
    required int priceAmountCents,
  }) async {
    final response = await _client.raw.post<Object?>(
      '/api/teachers/special-offers/execution',
      data: <String, Object?>{
        'course_ids': courseIds,
        'price_amount_cents': priceAmountCents,
      },
    );
    return SpecialOfferExecutionState.fromResponse(
      response.data,
      label: 'Created special-offer execution state',
    );
  }

  Future<SpecialOfferExecutionState> updateSpecialOfferExecution(
    String specialOfferId, {
    List<String>? courseIds,
    int? priceAmountCents,
  }) async {
    final response = await _client.raw.patch<Object?>(
      '/api/teachers/special-offers/$specialOfferId/execution',
      data: <String, Object?>{
        if (courseIds != null) 'course_ids': courseIds,
        if (priceAmountCents != null) 'price_amount_cents': priceAmountCents,
      },
    );
    return SpecialOfferExecutionState.fromResponse(
      response.data,
      label: 'Updated special-offer execution state',
    );
  }

  Future<SpecialOfferExecutionState> generateSpecialOfferImage(
    String specialOfferId,
  ) async {
    final response = await _client.raw.post<Object?>(
      '/api/teachers/special-offers/$specialOfferId/execution/generate',
    );
    return SpecialOfferExecutionState.fromResponse(
      response.data,
      label: 'Generated special-offer execution state',
    );
  }

  Future<SpecialOfferExecutionState> regenerateSpecialOfferImage(
    String specialOfferId, {
    required bool confirmOverwrite,
  }) async {
    final response = await _client.raw.post<Object?>(
      '/api/teachers/special-offers/$specialOfferId/execution/regenerate',
      data: <String, Object?>{'confirm_overwrite': confirmOverwrite},
    );
    return SpecialOfferExecutionState.fromResponse(
      response.data,
      label: 'Regenerated special-offer execution state',
    );
  }

  Future<SpecialOfferExecutionState> fetchSpecialOfferExecutionState(
    String specialOfferId,
  ) async {
    final response = await _client.raw.get<Object?>(
      '/api/teachers/special-offers/$specialOfferId/execution',
    );
    return SpecialOfferExecutionState.fromResponse(
      response.data,
      label: 'Special-offer execution state',
    );
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

  Future<List<CourseFamilyStudio>> myCourseFamilies() async {
    final response = await _client.raw.get<Object?>('/studio/course-families');
    final items = _requiredResponseListField(
      response.data,
      'items',
      'Studio course family list',
    );
    return items
        .map(
          (item) => CourseFamilyStudio.fromResponse(
            item,
            label: 'Studio course family list item',
          ),
        )
        .toList(growable: false);
  }

  Future<CourseFamilyStudio> createCourseFamily({required String name}) async {
    final response = await _client.raw.post<Object?>(
      '/studio/course-families',
      data: <String, Object?>{'name': name},
    );
    return CourseFamilyStudio.fromResponse(
      response.data,
      label: 'Created studio course family',
    );
  }

  Future<CourseFamilyStudio> renameCourseFamily(
    String courseFamilyId, {
    required String name,
  }) async {
    final response = await _client.raw.patch<Object?>(
      '/studio/course-families/$courseFamilyId',
      data: <String, Object?>{'name': name},
    );
    return CourseFamilyStudio.fromResponse(
      response.data,
      label: 'Renamed studio course family',
    );
  }

  Future<void> deleteCourseFamily(String courseFamilyId) async {
    await _client.delete('/studio/course-families/$courseFamilyId');
  }

  Future<CourseStudio> createCourse({
    required String title,
    required String slug,
    required String courseGroupId,
    required bool dripEnabled,
    required int? dripIntervalDays,
    int? priceAmountCents,
    String? coverMediaId,
  }) async {
    final response = await _client.raw.post<Object?>(
      '/studio/courses',
      data: <String, Object?>{
        'title': title,
        'slug': slug,
        'course_group_id': courseGroupId,
        'price_amount_cents': priceAmountCents,
        'drip_enabled': dripEnabled,
        'drip_interval_days': dripIntervalDays,
        'cover_media_id': coverMediaId,
      },
    );
    return CourseStudio.fromResponse(
      response.data,
      label: 'Created studio course',
    );
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
    if (patch.containsKey('course_group_id') ||
        patch.containsKey('group_position')) {
      throw UnsupportedError(
        'Use explicit course family transition operations for course_group_id/group_position changes',
      );
    }
    _rejectCourseDripAuthoringPatch(patch);
    final response = await _client.raw.patch<Object?>(
      '/studio/courses/$courseId',
      data: patch,
    );
    return CourseStudio.fromResponse(
      response.data,
      label: 'Updated studio course',
    );
  }

  Future<CourseStudio> updateCourseDripAuthoring(
    String courseId,
    Map<String, Object?> payload,
  ) async {
    _validateCourseDripAuthoringPayload(payload);
    final response = await _client.raw.put<Object?>(
      '/studio/courses/$courseId/drip-authoring',
      data: payload,
    );
    return CourseStudio.fromResponse(
      response.data,
      label: 'Updated studio course drip authoring',
    );
  }

  Future<CourseStudio> reorderCourseWithinFamily(
    String courseId, {
    required int groupPosition,
  }) async {
    final response = await _client.raw.post<Object?>(
      '/studio/courses/$courseId/reorder',
      data: <String, Object?>{'group_position': groupPosition},
    );
    return CourseStudio.fromResponse(
      response.data,
      label: 'Reordered studio course',
    );
  }

  Future<CourseStudio> moveCourseToFamily(
    String courseId, {
    required String courseGroupId,
  }) async {
    final response = await _client.raw.post<Object?>(
      '/studio/courses/$courseId/move-family',
      data: <String, Object?>{'course_group_id': courseGroupId},
    );
    return CourseStudio.fromResponse(
      response.data,
      label: 'Moved studio course',
    );
  }

  Future<CourseStudio> publishCourse(String courseId) async {
    final response = await _client.raw.post<Object?>(
      '/studio/courses/$courseId/publish',
    );
    return CourseStudio.fromResponse(
      response.data,
      label: 'Published studio course',
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
    required LessonDocument contentDocument,
    int position = 0,
  }) async {
    return _unsupportedRuntime(
      'Blandad lektionsstruktur och lektionsinnehåll stöds inte',
    );
  }

  Future<LessonStudio> createLessonStructure({
    required String courseId,
    required String lessonTitle,
    int position = 0,
  }) async {
    final body = <String, Object?>{
      'lesson_title': lessonTitle,
      'position': position,
    };
    final response = await _client.raw.post<Object?>(
      '/studio/courses/$courseId/lessons',
      data: body,
    );
    return LessonStudio.fromResponse(
      response.data,
      label: 'Created studio lesson structure',
    );
  }

  Future<LessonStudio> updateLessonStructure(
    String id, {
    required String lessonTitle,
    int position = 0,
  }) async {
    final body = <String, Object?>{
      'lesson_title': lessonTitle,
      'position': position,
    };
    final response = await _client.raw.patch<Object?>(
      '/studio/lessons/$id/structure',
      data: body,
    );
    return LessonStudio.fromResponse(
      response.data,
      label: 'Updated studio lesson structure',
    );
  }

  Future<StudioLessonContentRead> readLessonContent(String id) async {
    final response = await _client.raw.get<Object?>(
      '/studio/lessons/$id/content',
    );
    return StudioLessonContentRead.fromResponse(
      response.data,
      etag: _requiredEtagHeader(response, 'Studio lesson content read'),
    );
  }

  Future<StudioLessonContentWriteResult> updateLessonContent(
    String id, {
    required LessonDocument contentDocument,
    required String ifMatch,
  }) async {
    final contentToken = ifMatch.trim();
    if (contentToken.isEmpty) {
      throw StateError('Lektionsinnehåll kräver en giltig If-Match-token');
    }
    final response = await _client.raw.patch<Object?>(
      '/studio/lessons/$id/content',
      data: {'content_document': contentDocument.toJson()},
      options: Options(headers: {'If-Match': contentToken}),
    );
    return StudioLessonContentWriteResult.fromResponse(
      response.data,
      etag: _requiredEtagHeader(response, 'Updated studio lesson content'),
    );
  }

  Future<void> deleteLesson(String lessonId) async {
    await _client.delete('/studio/lessons/$lessonId');
  }

  static List<String> _lessonMediaIdsFromContent(
    StudioLessonContentRead content,
  ) {
    final ids = <String>[];
    final seen = <String>{};
    for (final media in content.media) {
      final id = media.lessonMediaId.trim();
      if (id.isEmpty || !seen.add(id)) {
        continue;
      }
      ids.add(id);
    }
    return ids;
  }

  Future<List<StudioLessonMediaItem>> listLessonMedia(String lessonId) async {
    final content = await readLessonContent(lessonId);
    if (content.lessonId != lessonId) {
      throw StateError('Lektionsinnehållet hör till fel lektion.');
    }
    return _lessonMedia.fetchLessonMediaPlacements(
      _lessonMediaIdsFromContent(content),
    );
  }

  Future<StudioLessonMediaPreviewBatch> fetchLessonMediaPreviews(
    List<String> lessonMediaIds,
  ) => _lessonMedia.fetchLessonMediaPreviews(lessonMediaIds);

  Future<List<StudioLessonMediaItem>> fetchLessonMediaPlacements(
    List<String> lessonMediaIds,
  ) => _lessonMedia.fetchLessonMediaPlacements(lessonMediaIds);

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
    final response = await _client.raw.get<Object?>(
      '/studio/home-player/library',
    );
    return HomePlayerLibraryPayload.fromJson(
      Map<String, dynamic>.from(
        _requiredResponseMap(response.data, 'Home player library'),
      ),
    );
  }

  Future<HomePlayerUploadItem> uploadHomePlayerUpload({
    required String title,
    required String mediaAssetId,
    bool active = true,
  }) async {
    final response = await _client.raw.post<Object?>(
      '/studio/home-player/uploads',
      data: <String, Object?>{
        'title': title,
        'media_asset_id': mediaAssetId,
        'active': active,
      },
    );
    return HomePlayerUploadItem.fromJson(
      Map<String, dynamic>.from(
        _requiredResponseMap(response.data, 'Created home player upload'),
      ),
    );
  }

  Future<Map<String, Object?>> requestHomePlayerUploadUrl({
    required String filename,
    required String mimeType,
    required int sizeBytes,
  }) async {
    final response = await _client.raw.post<Object?>(
      '/api/home-player/media-assets/upload-url',
      data: <String, Object?>{
        'filename': filename,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
      },
    );
    return _requiredResponseMap(response.data, 'Home player upload URL');
  }

  Future<Map<String, Object?>> refreshHomePlayerUploadUrl({
    required String objectPath,
    required String mimeType,
  }) async {
    // Canonical backend refresh endpoint is not available for this surface yet.
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
    // Canonical backend does not expose storage-backed home player creation here.
    return _unsupportedRuntime('Home player storage uploads');
  }

  Future<HomePlayerUploadItem> updateHomePlayerUpload(
    String uploadId, {
    String? title,
    bool? active,
  }) async {
    final patch = <String, Object?>{};
    if (title != null) {
      patch['title'] = title;
    }
    if (active != null) {
      patch['active'] = active;
    }
    final response = await _client.raw.patch<Object?>(
      '/studio/home-player/uploads/$uploadId',
      data: patch,
    );
    return HomePlayerUploadItem.fromJson(
      Map<String, dynamic>.from(
        _requiredResponseMap(response.data, 'Updated home player upload'),
      ),
    );
  }

  Future<void> deleteHomePlayerUpload(String uploadId) async {
    await _client.delete('/studio/home-player/uploads/$uploadId');
  }

  Future<HomePlayerCourseLinkItem> createHomePlayerCourseLink({
    required String lessonMediaId,
    required String title,
    bool enabled = true,
  }) async {
    final response = await _client.raw.post<Object?>(
      '/studio/home-player/course-links',
      data: <String, Object?>{
        'lesson_media_id': lessonMediaId,
        'title': title,
        'enabled': enabled,
      },
    );
    return HomePlayerCourseLinkItem.fromJson(
      Map<String, dynamic>.from(
        _requiredResponseMap(response.data, 'Created home player course link'),
      ),
    );
  }

  Future<HomePlayerCourseLinkItem> updateHomePlayerCourseLink(
    String linkId, {
    bool? enabled,
    String? title,
  }) async {
    final patch = <String, Object?>{};
    if (enabled != null) {
      patch['enabled'] = enabled;
    }
    if (title != null) {
      patch['title'] = title;
    }
    final response = await _client.raw.patch<Object?>(
      '/studio/home-player/course-links/$linkId',
      data: patch,
    );
    return HomePlayerCourseLinkItem.fromJson(
      Map<String, dynamic>.from(
        _requiredResponseMap(response.data, 'Updated home player course link'),
      ),
    );
  }

  Future<void> deleteHomePlayerCourseLink(String linkId) async {
    await _client.delete('/studio/home-player/course-links/$linkId');
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
}

class StudioStatus {
  const StudioStatus({required this.isTeacher, required this.hasApplication});

  final bool isTeacher;
  final bool hasApplication;

  factory StudioStatus.fromResponse(Object? payload) {
    final role = StudioRepository._requiredResponseField(
      payload,
      'role',
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
    if (hasApplication is! bool) {
      throw StateError('Studio status field "has_application" must be a bool');
    }
    return StudioStatus(
      isTeacher: role == 'teacher',
      hasApplication: hasApplication,
    );
  }
}
