import 'dart:async';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/shared/utils/course_cover_contract.dart';
import 'package:aveli/shared/utils/course_journey_step.dart';

class CoursesRepository {
  CoursesRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<List<CourseSummary>> fetchPublishedCourses({
    bool onlyFreeIntro = false,
  }) async {
    try {
      final params = <String, dynamic>{'published_only': true};
      final res = await _client.get<Map<String, dynamic>>(
        '/courses',
        queryParameters: params,
      );
      final items = (res['items'] as List? ?? const [])
          .map(
            (e) => CourseSummary.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      if (!onlyFreeIntro) {
        return items;
      }
      return items
          .where((course) => course.step == CourseJourneyStep.intro)
          .toList(growable: false);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<List<CourseSummary>> myEnrolledCourses() async {
    try {
      final res = await _client.get<Map<String, dynamic>>('/courses/me');
      final items = (res['items'] as List? ?? [])
          .map(
            (e) => CourseSummary.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      return items;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<CourseSummary?> getCourseById(String courseId) async {
    try {
      final res = await _client.get<Map<String, dynamic>>('/courses/$courseId');
      final course = res['course'];
      if (course is Map<String, dynamic>) {
        return CourseSummary.fromJson(course);
      }
      return null;
    } catch (error, stackTrace) {
      if (error is AppFailure && error.kind == AppFailureKind.notFound) {
        return null;
      }
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<CourseDetailData> fetchCourseDetailBySlug(String slug) async {
    try {
      final encoded = Uri.encodeComponent(slug);
      final res = await _client.get<Map<String, dynamic>>(
        '/courses/by-slug/$encoded',
      );
      return _mapCourseDetail(res);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<CourseDetailData> fetchCourseDetailById(String courseId) async {
    try {
      final res = await _client.get<Map<String, dynamic>>('/courses/$courseId');
      return _mapCourseDetail(res);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  CourseDetailData _mapCourseDetail(Map<String, dynamic> payload) {
    final course = CourseSummary.fromJson(
      Map<String, dynamic>.from(payload['course'] as Map),
    );
    final lessons = (payload['lessons'] as List? ?? []).toList();
    final lessonItems =
        lessons
            .map(
              (e) =>
                  LessonSummary.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(growable: false)
          ..sort((a, b) => a.position.compareTo(b.position));
    return CourseDetailData(course: course, lessons: lessonItems);
  }

  Future<CourseSummary?> firstFreeIntroCourse() async {
    try {
      final courses = await fetchPublishedCourses();
      for (final course in courses) {
        if (course.step == CourseJourneyStep.intro) {
          return course;
        }
      }
      return null;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<LessonDetailData> fetchLessonDetail(String lessonId) async {
    try {
      final res = await _client.get<Map<String, dynamic>>(
        '/courses/lessons/$lessonId',
      );
      final lesson = LessonDetail.fromJson(
        Map<String, dynamic>.from(res['lesson'] as Map),
      );
      final courseId = (res['course_id'] as String?)?.trim();
      final lessons =
          (res['lessons'] as List? ?? [])
              .map(
                (e) =>
                    LessonSummary.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList(growable: false)
            ..sort((a, b) => a.position.compareTo(b.position));
      final media = (res['media'] as List? ?? [])
          .map(
            (e) =>
                LessonMediaItem.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      return LessonDetailData(
        lesson: lesson,
        courseId: courseId == null || courseId.isEmpty ? null : courseId,
        lessons: lessons,
        media: media,
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<CourseAccessData> enrollCourse(String courseId) async {
    try {
      final res = await _client.post<Map<String, dynamic>>(
        '/courses/$courseId/enroll',
      );
      return CourseAccessData.fromJson(res);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<CourseAccessData> fetchCourseState(String courseId) async {
    try {
      return await _fetchCourseAccess(courseId);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<CourseAccessData> _fetchCourseAccess(String courseId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/courses/$courseId/access',
    );
    return CourseAccessData.fromJson(res);
  }

  Future<CourseQuizInfo> fetchQuizInfo(String courseId) async {
    try {
      final res = await _client.get<Map<String, dynamic>>(
        '/courses/$courseId/quiz',
      );
      return CourseQuizInfo.fromJson(res);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<List<QuizQuestion>> fetchQuizQuestions(String quizId) async {
    try {
      final res = await _client.get<Map<String, dynamic>>(
        '/courses/quiz/$quizId/questions',
      );
      return (res['items'] as List? ?? [])
          .map(
            (e) => QuizQuestion.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> submitQuiz({
    required String quizId,
    required Map<String, dynamic> answers,
  }) async {
    try {
      final res = await _client.post<Map<String, dynamic>>(
        '/courses/quiz/$quizId/submit',
        body: {'answers': answers},
      );
      return res;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}

class CourseDetailData {
  CourseDetailData({required this.course, required this.lessons});

  final CourseSummary course;
  final List<LessonSummary> lessons;
}

class CourseEnrollmentRecord {
  const CourseEnrollmentRecord({
    required this.id,
    required this.userId,
    required this.courseId,
    required this.source,
    required this.grantedAt,
    required this.dripStartedAt,
    required this.currentUnlockPosition,
  });

  final String id;
  final String userId;
  final String courseId;
  final String source;
  final DateTime grantedAt;
  final DateTime dripStartedAt;
  final int currentUnlockPosition;

  factory CourseEnrollmentRecord.fromJson(Map<String, dynamic> json) =>
      CourseEnrollmentRecord(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        courseId: json['course_id'] as String,
        source: (json['source'] as String?) ?? '',
        grantedAt: DateTime.parse(json['granted_at'] as String).toUtc(),
        dripStartedAt: DateTime.parse(
          json['drip_started_at'] as String,
        ).toUtc(),
        currentUnlockPosition:
            CourseSummary._asInt(json['current_unlock_position']) ?? 0,
      );
}

class CourseAccessData {
  const CourseAccessData({
    required this.courseId,
    required this.courseStep,
    required this.requiredEnrollmentSource,
    required this.enrollment,
  });

  final String courseId;
  final CourseJourneyStep? courseStep;
  final String? requiredEnrollmentSource;
  final CourseEnrollmentRecord? enrollment;

  bool get hasEnrollment => enrollment != null;

  int get currentUnlockPosition => enrollment?.currentUnlockPosition ?? 0;

  factory CourseAccessData.fromJson(Map<String, dynamic> json) {
    final enrollmentMap = json['enrollment'];
    return CourseAccessData(
      courseId: (json['course_id'] as String?) ?? '',
      courseStep: courseJourneyStepFromApi(json['course_step']),
      requiredEnrollmentSource: (json['required_enrollment_source'] as String?)
          ?.trim(),
      enrollment: enrollmentMap is Map
          ? CourseEnrollmentRecord.fromJson(
              Map<String, dynamic>.from(enrollmentMap),
            )
          : null,
    );
  }
}

class LessonDetailData {
  const LessonDetailData({
    required this.lesson,
    this.courseId,
    this.lessons = const [],
    this.media = const [],
  });

  final LessonDetail lesson;
  final String? courseId;
  final List<LessonSummary> lessons;
  final List<LessonMediaItem> media;
}

class CourseSummary {
  const CourseSummary({
    required this.id,
    this.slug,
    required this.title,
    this.step,
    this.courseGroupId,
    this.description,
    this.coverMediaId,
    this.cover,
    this.videoUrl,
    this.branch,
    this.stepLevel,
    this.courseFamily,
    this.createdBy,
    this.isFreeIntro = false,
    this.journeyStep,
    this.isPublished = false,
    this.priceCents,
  });

  final String id;
  final String? slug;
  final String title;
  final CourseJourneyStep? step;
  final String? courseGroupId;
  final String? description;
  final String? coverMediaId;
  final CourseCoverData? cover;
  final String? videoUrl;
  final String? branch;
  final CourseJourneyStep? stepLevel;
  final String? courseFamily;
  final String? createdBy;
  final bool isFreeIntro;
  final CourseJourneyStep? journeyStep;
  final bool isPublished;
  final int? priceCents;

  bool get isIntroCourse => step == CourseJourneyStep.intro;

  factory CourseSummary.fromJson(Map<String, dynamic> json) => CourseSummary(
    id: json['id'] as String,
    slug: json['slug'] as String?,
    title: (json['title'] ?? '') as String,
    step: courseJourneyStepFromApi(json['step']),
    courseGroupId: json['course_group_id'] as String?,
    description: json['description'] as String?,
    coverMediaId: json['cover_media_id'] as String?,
    cover: json['cover'] is Map
        ? CourseCoverData.fromJson(
            Map<String, dynamic>.from(json['cover'] as Map),
          )
        : null,
    videoUrl: json['video_url'] as String?,
    branch: json['branch'] as String?,
    stepLevel: courseJourneyStepFromApi(json['step']),
    courseFamily: json['course_family'] as String?,
    createdBy: json['created_by'] as String?,
    isFreeIntro:
        courseJourneyStepFromApi(json['step']) == CourseJourneyStep.intro,
    journeyStep: courseJourneyStepFromApi(json['step']),
    isPublished: json['is_published'] == true,
    priceCents: _asInt(json['price_amount_cents']),
  );

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class LessonSummary {
  const LessonSummary({
    required this.id,
    required this.title,
    required this.position,
    this.isIntro = false,
    this.contentMarkdown,
  });

  final String id;
  final String title;
  final int position;
  final bool isIntro;
  final String? contentMarkdown;

  factory LessonSummary.fromJson(Map<String, dynamic> json) => LessonSummary(
    id: json['id'] as String,
    title: (json['title'] ?? '') as String,
    position: CourseSummary._asInt(json['position']) ?? 0,
    isIntro: json['is_intro'] == true,
    contentMarkdown: json['content_markdown'] as String?,
  );
}

class LessonDetail {
  const LessonDetail({
    required this.id,
    required this.title,
    this.contentMarkdown,
    this.isIntro = false,
    this.position = 0,
  });

  final String id;
  final String title;
  final String? contentMarkdown;
  final bool isIntro;
  final int position;

  factory LessonDetail.fromJson(Map<String, dynamic> json) => LessonDetail(
    id: json['id'] as String,
    title: (json['title'] ?? '') as String,
    contentMarkdown: json['content_markdown'] as String?,
    isIntro: json['is_intro'] == true,
    position: CourseSummary._asInt(json['position']) ?? 0,
  );
}

class LessonMediaItem {
  const LessonMediaItem({
    required this.id,
    required this.kind,
    required this.storagePath,
    this.storageBucket,
    this.preferredUrlValue,
    this.playbackUrl,
    this.downloadUrl,
    this.signedUrl,
    this.signedUrlExpiresAt,
    this.mediaId,
    this.mediaAssetId,
    this.durationSeconds,
    this.byteSize,
    this.contentType,
    this.originalName,
    this.position = 0,
    this.mediaState,
    this.streamingFormat,
    this.codec,
    this.errorMessage,
    this.robustnessCategory,
    this.robustnessStatus,
    this.robustnessRecommendedAction,
    this.resolvableForEditor,
    this.resolvableForStudent,
  });

  final String id;
  final String kind;
  final String storagePath;
  final String? storageBucket;
  final String? preferredUrlValue;
  final String? playbackUrl;
  final String? downloadUrl;
  final String? signedUrl;
  final DateTime? signedUrlExpiresAt;
  final String? mediaId;
  final String? mediaAssetId;
  final int? durationSeconds;
  final int? byteSize;
  final String? contentType;
  final String? originalName;
  final int position;
  final String? mediaState;
  final String? streamingFormat;
  final String? codec;
  final String? errorMessage;
  final String? robustnessCategory;
  final String? robustnessStatus;
  final String? robustnessRecommendedAction;
  final bool? resolvableForEditor;
  final bool? resolvableForStudent;

  factory LessonMediaItem.fromJson(Map<String, dynamic> json) =>
      LessonMediaItem(
        id: json['id'] as String,
        kind: (json['kind'] ?? '') as String,
        storagePath: (json['storage_path'] ?? '') as String,
        storageBucket: json['storage_bucket'] as String?,
        preferredUrlValue:
            json['preferredUrl'] as String? ?? json['preferred_url'] as String?,
        playbackUrl: json['playback_url'] as String?,
        downloadUrl: json['download_url'] as String?,
        signedUrl: json['signed_url'] as String?,
        signedUrlExpiresAt: CourseOrderSummary._parseDate(
          json['signed_url_expires_at'],
        ),
        mediaId: json['media_id'] as String?,
        mediaAssetId: json['media_asset_id'] as String?,
        durationSeconds: CourseSummary._asInt(json['duration_seconds']),
        byteSize: CourseSummary._asInt(json['byte_size']),
        contentType: json['content_type'] as String?,
        originalName: json['original_name'] as String?,
        position: CourseSummary._asInt(json['position']) ?? 0,
        mediaState: json['media_state'] as String?,
        streamingFormat: json['streaming_format'] as String?,
        codec: json['codec'] as String?,
        errorMessage: json['error_message'] as String?,
        robustnessCategory: json['robustness_category'] as String?,
        robustnessStatus: json['robustness_status'] as String?,
        robustnessRecommendedAction:
            json['robustness_recommended_action'] as String?,
        resolvableForEditor: json['resolvable_for_editor'] as bool?,
        resolvableForStudent: json['resolvable_for_student'] as bool?,
      );

  bool get isPublicBucket => (storageBucket ?? '').startsWith('public');

  String get fileName {
    final normalizedOriginalName = originalName?.trim();
    if (normalizedOriginalName != null && normalizedOriginalName.isNotEmpty) {
      return normalizedOriginalName;
    }
    return 'media_$id';
  }

  String? get preferredUrl {
    final explicit = preferredUrlValue?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    for (final candidate in <String?>[playbackUrl, downloadUrl, signedUrl]) {
      final normalized = candidate?.trim();
      if (normalized == null || normalized.isEmpty) {
        continue;
      }
      final uri = Uri.tryParse(normalized);
      final scheme = uri?.scheme.toLowerCase();
      if (uri != null &&
          uri.hasScheme &&
          (scheme == 'http' || scheme == 'https') &&
          uri.host.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }
}

class CourseOrderSummary {
  const CourseOrderSummary({
    required this.id,
    required this.status,
    this.amountCents,
    required this.createdAt,
  });

  final String id;
  final String status;
  final int? amountCents;
  final DateTime createdAt;

  factory CourseOrderSummary.fromJson(Map<String, dynamic> json) =>
      CourseOrderSummary(
        id: json['id'] as String,
        status: (json['status'] ?? '') as String,
        amountCents: CourseSummary._asInt(json['amount_cents']),
        createdAt: _parseDate(json['created_at']),
      );

  static DateTime _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }
}

class CourseQuizInfo {
  const CourseQuizInfo({this.quizId, this.certified = false});

  final String? quizId;
  final bool certified;

  factory CourseQuizInfo.fromJson(Map<String, dynamic> json) => CourseQuizInfo(
    quizId: json['quiz_id'] as String?,
    certified: json['certified'] == true,
  );
}

class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.position,
    required this.kind,
    required this.prompt,
    required this.options,
  });

  final String id;
  final int position;
  final String kind;
  final String prompt;
  final List<String> options;

  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
    id: json['id'] as String,
    position: CourseSummary._asInt(json['position']) ?? 0,
    kind: (json['kind'] ?? '') as String,
    prompt: (json['prompt'] ?? '') as String,
    options: _parseOptions(json['options']),
  );
}

List<String> _parseOptions(Object? rawOptions) {
  if (rawOptions is List) {
    return rawOptions.map((value) => value.toString()).toList(growable: false);
  }
  if (rawOptions is Map) {
    return rawOptions.values
        .map((value) => value.toString())
        .toList(growable: false);
  }
  if (rawOptions is String && rawOptions.trim().isNotEmpty) {
    return rawOptions.split('\n').map((value) => value.trim()).toList();
  }
  return const <String>[];
}
