import 'dart:async';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/shared/utils/course_cover_contract.dart';
import 'package:aveli/shared/utils/resolved_media_contract.dart';

const Set<String> _legacyCourseCoverFields = <String>{
  'cover_url',
  'coverUrl',
  'resolved_cover_url',
  'resolvedCoverUrl',
  'signed_cover_url',
  'signedCoverUrl',
  'signed_cover_url_expires_at',
  'signedCoverUrlExpiresAt',
};

const Set<String> _legacyCourseProgressionFields = <String>{'step'};

Object? _requiredField(Object? payload, String fieldName) {
  switch (payload) {
    case final Map data when data.containsKey(fieldName):
      return data[fieldName];
    case final Map _:
      throw StateError('Missing required field: $fieldName');
    default:
      throw StateError('Invalid payload for $fieldName');
  }
}

void _rejectLegacyCourseCoverFields(Object? payload, String context) {
  if (payload case final Map data) {
    for (final field in _legacyCourseCoverFields) {
      if (data.containsKey(field)) {
        throw StateError('Invalid course cover field in $context');
      }
    }
  }
}

void _rejectLegacyCourseProgressionFields(Object? payload, String context) {
  if (payload case final Map data) {
    for (final field in _legacyCourseProgressionFields) {
      if (data.containsKey(field)) {
        throw StateError('Ogiltigt kursprogressionsf\u00e4lt i $context');
      }
    }
  }
}

String _requireString(Object? value, String fieldName) {
  switch (value) {
    case final String text when text.isNotEmpty:
      return text;
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

String? _optionalString(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    case final String text:
      return text;
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

int _requireInt(Object? value, String fieldName) {
  switch (value) {
    case final int number:
      return number;
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

int? _optionalInt(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    case final int number:
      return number;
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

bool _requireBool(Object? value, String fieldName) {
  switch (value) {
    case final bool flag:
      return flag;
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

CourseCoverData? _optionalCourseCover(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    case final Map<String, dynamic> data:
      return CourseCoverData.fromJson(data);
    case final Map data:
      return CourseCoverData.fromJson(Map<String, dynamic>.from(data));
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

CourseTeacherData? _optionalCourseTeacher(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    case final Map<String, dynamic> data:
      return CourseTeacherData.fromResponse(data);
    case final Map data:
      return CourseTeacherData.fromResponse(Map<String, dynamic>.from(data));
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

DateTime _requireDateTime(Object? value, String fieldName) {
  final raw = _requireString(value, fieldName);
  return DateTime.parse(raw);
}

int _requireGroupPosition(Object? value, String fieldName) {
  final position = _requireInt(value, fieldName);
  if (position < 0) {
    throw StateError('Invalid field value for $fieldName');
  }
  return position;
}

List<Object?> _requireList(Object? value, String fieldName) {
  switch (value) {
    case final List items:
      return List<Object?>.unmodifiable(items);
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

class CoursesRepository {
  CoursesRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<List<CourseSummary>> fetchPublishedCourses({
    bool onlyFreeIntro = false,
  }) async {
    try {
      final response = await _client.raw.get<Object?>(
        '/courses',
        queryParameters: const <String, Object?>{'published_only': true},
      );
      final items = switch (response.data) {
        {'items': final List items} =>
          items.map(CourseSummary.fromResponse).toList(growable: false),
        _ => throw StateError('Invalid course list payload'),
      };
      if (!onlyFreeIntro) {
        return items;
      }
      return items
          .where((course) => course.isIntroCourse)
          .toList(growable: false);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<List<CourseSummary>> myEnrolledCourses() async {
    try {
      final response = await _client.raw.get<Object?>('/courses/me');
      return switch (response.data) {
        {'items': final List items} =>
          items.map(CourseSummary.fromResponse).toList(growable: false),
        _ => throw StateError('Invalid course list payload'),
      };
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<CourseSummary?> getCourseById(String courseId) async {
    try {
      final detail = await fetchCourseDetailById(courseId);
      return detail.course;
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
      final response = await _client.raw.get<Object?>(
        '/courses/by-slug/$encoded',
      );
      return CourseDetailData.fromResponse(response.data);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<CourseDetailData> fetchCourseDetailById(String courseId) async {
    try {
      final response = await _client.raw.get<Object?>('/courses/$courseId');
      return CourseDetailData.fromResponse(response.data);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<CourseSummary?> firstFreeIntroCourse() async {
    try {
      final courses = await fetchPublishedCourses();
      for (final course in courses) {
        if (course.isIntroCourse) {
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
      final response = await _client.raw.get<Object?>(
        '/courses/lessons/$lessonId',
      );
      return LessonDetailData.fromResponse(response.data);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<CourseAccessData> enrollCourse(String courseId) async {
    try {
      final response = await _client.raw.post<Object?>(
        '/courses/$courseId/enroll',
      );
      return CourseAccessData.fromResponse(response.data);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<CourseAccessData> fetchCourseState(String courseId) async {
    try {
      final response = await _client.raw.get<Object?>(
        '/courses/$courseId/access',
      );
      return CourseAccessData.fromResponse(response.data);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}

class CourseDetailData {
  const CourseDetailData({
    required this.course,
    required this.lessons,
    required this.shortDescription,
  });

  final CourseSummary course;
  final List<LessonSummary> lessons;
  final String? shortDescription;

  factory CourseDetailData.fromResponse(Object? payload) {
    final lessons =
        _requireList(
            _requiredField(payload, 'lessons'),
            'lessons',
          ).map(LessonSummary.fromResponse).toList(growable: false)
          ..sort((a, b) => a.position.compareTo(b.position));
    return CourseDetailData(
      course: CourseSummary.fromResponse(_requiredField(payload, 'course')),
      lessons: lessons,
      shortDescription: _optionalString(
        _requiredField(payload, 'short_description'),
        'short_description',
      ),
    );
  }
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

  factory CourseEnrollmentRecord.fromResponse(Object? payload) {
    return CourseEnrollmentRecord(
      id: _requireString(_requiredField(payload, 'id'), 'id'),
      userId: _requireString(_requiredField(payload, 'user_id'), 'user_id'),
      courseId: _requireString(
        _requiredField(payload, 'course_id'),
        'course_id',
      ),
      source: _requireString(_requiredField(payload, 'source'), 'source'),
      grantedAt: _requireDateTime(
        _requiredField(payload, 'granted_at'),
        'granted_at',
      ),
      dripStartedAt: _requireDateTime(
        _requiredField(payload, 'drip_started_at'),
        'drip_started_at',
      ),
      currentUnlockPosition: _requireInt(
        _requiredField(payload, 'current_unlock_position'),
        'current_unlock_position',
      ),
    );
  }
}

class CourseAccessData {
  const CourseAccessData({
    required this.courseId,
    required this.groupPosition,
    required this.requiredEnrollmentSource,
    required this.enrollable,
    required this.purchasable,
    required this.canAccess,
    required this.enrollment,
  });

  final String courseId;
  final int groupPosition;
  final String? requiredEnrollmentSource;
  final bool enrollable;
  final bool purchasable;
  final bool canAccess;
  final CourseEnrollmentRecord? enrollment;

  factory CourseAccessData.fromResponse(Object? payload) {
    _rejectLegacyCourseProgressionFields(payload, 'course_access');
    final enrollmentPayload = _requiredField(payload, 'enrollment');
    return CourseAccessData(
      courseId: _requireString(
        _requiredField(payload, 'course_id'),
        'course_id',
      ),
      groupPosition: _requireGroupPosition(
        _requiredField(payload, 'group_position'),
        'group_position',
      ),
      requiredEnrollmentSource: _optionalString(
        _requiredField(payload, 'required_enrollment_source'),
        'required_enrollment_source',
      ),
      enrollable: _requireBool(
        _requiredField(payload, 'enrollable'),
        'enrollable',
      ),
      purchasable: _requireBool(
        _requiredField(payload, 'purchasable'),
        'purchasable',
      ),
      canAccess: _requireBool(
        _requiredField(payload, 'can_access'),
        'can_access',
      ),
      enrollment: enrollmentPayload == null
          ? null
          : CourseEnrollmentRecord.fromResponse(enrollmentPayload),
    );
  }
}

class LessonDetailData {
  const LessonDetailData({
    required this.lesson,
    required this.courseId,
    required this.lessons,
    required this.media,
  });

  final LessonDetail lesson;
  final String courseId;
  final List<LessonSummary> lessons;
  final List<LessonMediaItem> media;

  factory LessonDetailData.fromResponse(Object? payload) {
    final lessons =
        _requireList(
            _requiredField(payload, 'lessons'),
            'lessons',
          ).map(LessonSummary.fromResponse).toList(growable: false)
          ..sort((a, b) => a.position.compareTo(b.position));
    final media = _requireList(
      _requiredField(payload, 'media'),
      'media',
    ).map(LessonMediaItem.fromResponse).toList(growable: false);
    return LessonDetailData(
      lesson: LessonDetail.fromResponse(_requiredField(payload, 'lesson')),
      courseId: _requireString(
        _requiredField(payload, 'course_id'),
        'course_id',
      ),
      lessons: lessons,
      media: media,
    );
  }
}

class CourseSummary {
  const CourseSummary({
    required this.id,
    required this.slug,
    required this.title,
    required this.teacher,
    required this.groupPosition,
    required this.courseGroupId,
    required this.coverMediaId,
    required this.cover,
    required this.priceCents,
    required this.dripEnabled,
    required this.dripIntervalDays,
    required this.requiredEnrollmentSource,
    required this.enrollable,
    required this.purchasable,
  });

  final String id;
  final String slug;
  final String title;
  final CourseTeacherData? teacher;
  final int groupPosition;
  final String courseGroupId;
  final String? coverMediaId;
  final CourseCoverData? cover;
  final int? priceCents;
  final bool dripEnabled;
  final int? dripIntervalDays;
  final String? requiredEnrollmentSource;
  final bool enrollable;
  final bool purchasable;

  bool get isIntroCourse => enrollable && !purchasable;

  factory CourseSummary.fromResponse(Object? payload) {
    _rejectLegacyCourseCoverFields(payload, 'course');
    _rejectLegacyCourseProgressionFields(payload, 'course');
    return CourseSummary(
      id: _requireString(_requiredField(payload, 'id'), 'id'),
      slug: _requireString(_requiredField(payload, 'slug'), 'slug'),
      title: _requireString(_requiredField(payload, 'title'), 'title'),
      teacher: _optionalCourseTeacher(
        _requiredField(payload, 'teacher'),
        'teacher',
      ),
      groupPosition: _requireGroupPosition(
        _requiredField(payload, 'group_position'),
        'group_position',
      ),
      courseGroupId: _requireString(
        _requiredField(payload, 'course_group_id'),
        'course_group_id',
      ),
      coverMediaId: _optionalString(
        _requiredField(payload, 'cover_media_id'),
        'cover_media_id',
      ),
      cover: _optionalCourseCover(_requiredField(payload, 'cover'), 'cover'),
      priceCents: _optionalInt(
        _requiredField(payload, 'price_amount_cents'),
        'price_amount_cents',
      ),
      dripEnabled: _requireBool(
        _requiredField(payload, 'drip_enabled'),
        'drip_enabled',
      ),
      dripIntervalDays: _optionalInt(
        _requiredField(payload, 'drip_interval_days'),
        'drip_interval_days',
      ),
      requiredEnrollmentSource: _optionalString(
        _requiredField(payload, 'required_enrollment_source'),
        'required_enrollment_source',
      ),
      enrollable: _requireBool(
        _requiredField(payload, 'enrollable'),
        'enrollable',
      ),
      purchasable: _requireBool(
        _requiredField(payload, 'purchasable'),
        'purchasable',
      ),
    );
  }
}

class CourseTeacherData {
  const CourseTeacherData({required this.userId, required this.displayName});

  final String userId;
  final String? displayName;

  factory CourseTeacherData.fromResponse(Object? payload) {
    return CourseTeacherData(
      userId: _requireString(_requiredField(payload, 'user_id'), 'user_id'),
      displayName: _optionalString(
        _requiredField(payload, 'display_name'),
        'display_name',
      ),
    );
  }
}

class LessonSummary {
  const LessonSummary({
    required this.id,
    required this.lessonTitle,
    required this.position,
  });

  final String id;
  final String lessonTitle;
  final int position;

  factory LessonSummary.fromResponse(Object? payload) {
    return LessonSummary(
      id: _requireString(_requiredField(payload, 'id'), 'id'),
      lessonTitle: _requireString(
        _requiredField(payload, 'lesson_title'),
        'lesson_title',
      ),
      position: _requireInt(_requiredField(payload, 'position'), 'position'),
    );
  }
}

class LessonDetail {
  const LessonDetail({
    required this.id,
    required this.lessonTitle,
    required this.contentMarkdown,
    required this.position,
  });

  final String id;
  final String lessonTitle;
  final String? contentMarkdown;
  final int position;

  factory LessonDetail.fromResponse(Object? payload) {
    return LessonDetail(
      id: _requireString(_requiredField(payload, 'id'), 'id'),
      lessonTitle: _requireString(
        _requiredField(payload, 'lesson_title'),
        'lesson_title',
      ),
      contentMarkdown: _optionalString(
        _requiredField(payload, 'content_markdown'),
        'content_markdown',
      ),
      position: _requireInt(_requiredField(payload, 'position'), 'position'),
    );
  }
}

class LessonMediaItem {
  const LessonMediaItem({
    required this.id,
    required this.lessonId,
    required this.mediaAssetId,
    required this.position,
    required this.mediaType,
    required this.state,
    required this.media,
  });

  final String id;
  final String lessonId;
  final String? mediaAssetId;
  final int position;
  final String mediaType;
  final String state;
  final ResolvedMediaData? media;

  factory LessonMediaItem.fromResponse(Object? payload) {
    return LessonMediaItem(
      id: _requireString(_requiredField(payload, 'id'), 'id'),
      lessonId: _requireString(
        _requiredField(payload, 'lesson_id'),
        'lesson_id',
      ),
      mediaAssetId: _optionalString(
        _requiredField(payload, 'media_asset_id'),
        'media_asset_id',
      ),
      position: _requireInt(_requiredField(payload, 'position'), 'position'),
      mediaType: _requireString(
        _requiredField(payload, 'media_type'),
        'media_type',
      ),
      state: _requireString(_requiredField(payload, 'state'), 'state'),
      media: _optionalResolvedMedia(_requiredField(payload, 'media'), 'media'),
    );
  }
}

ResolvedMediaData? _optionalResolvedMedia(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    case final Map<String, dynamic> data:
      return ResolvedMediaData.fromJson(data);
    case final Map data:
      return ResolvedMediaData.fromJson(Map<String, dynamic>.from(data));
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}
