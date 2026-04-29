import 'dart:async';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/courses/data/lesson_view_surface.dart';
import 'package:aveli/shared/utils/course_cover_contract.dart';

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

DateTime? _optionalDateTime(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    case final String raw:
      return DateTime.parse(raw);
    default:
      throw StateError('Invalid field type for $fieldName');
  }
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

Map<String, Object?> _requireMap(Object? value, String fieldName) {
  switch (value) {
    case final Map<String, Object?> data:
      return Map<String, Object?>.unmodifiable(data);
    case final Map<String, dynamic> data:
      return Map<String, Object?>.unmodifiable(data);
    case final Map data:
      return Map<String, Object?>.unmodifiable(data);
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

Map<String, Object?>? _optionalMap(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    default:
      return _requireMap(value, fieldName);
  }
}

const Set<String> _courseEntryRuntimeFields = <String>{
  'content_document',
  'content_markdown',
  'lesson_media_id',
  'media_id',
  'resolved_url',
};

void _rejectCourseEntryRuntimeFields(Object? value, String context) {
  switch (value) {
    case final Map data:
      for (final key in data.keys) {
        if (_courseEntryRuntimeFields.contains(key)) {
          throw StateError('Invalid course entry runtime field in $context');
        }
      }
      for (final entry in data.entries) {
        _rejectCourseEntryRuntimeFields(entry.value, '$context.${entry.key}');
      }
    case final Iterable items:
      for (final item in items) {
        _rejectCourseEntryRuntimeFields(item, context);
      }
  }
}

class CoursesRepository {
  CoursesRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<List<CourseSummary>> fetchPublishedCourses() async {
    try {
      final response = await _client.raw.get<Object?>(
        '/courses',
        queryParameters: const <String, Object?>{'published_only': true},
      );
      return switch (response.data) {
        {'items': final List items} =>
          items.map(CourseSummary.fromResponse).toList(growable: false),
        _ => throw StateError('Invalid course list payload'),
      };
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<IntroSelectionStateData> fetchIntroSelectionState() async {
    try {
      final response = await _client.raw.get<Object?>(
        '/courses/intro-selection',
      );
      return IntroSelectionStateData.fromResponse(response.data);
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

  Future<CourseEntryViewData> fetchCourseEntryView(
    String courseIdOrSlug,
  ) async {
    try {
      final encoded = Uri.encodeComponent(courseIdOrSlug);
      final response = await _client.raw.get<Object?>(
        '/courses/$encoded/entry-view',
      );
      return CourseEntryViewData.fromResponse(response.data);
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

  Future<LessonViewSurface> fetchLessonDetail(String lessonId) async {
    try {
      final response = await _client.raw.get<Object?>(
        '/courses/lessons/$lessonId',
      );
      return LessonViewSurface.fromResponse(response.data);
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

class CourseEntryViewData {
  const CourseEntryViewData({
    required this.course,
    required this.lessons,
    required this.access,
    required this.cta,
    required this.pricing,
    required this.nextRecommendedLesson,
  });

  final CourseEntryCourseData course;
  final List<CourseEntryLessonShellData> lessons;
  final CourseEntryAccessData access;
  final CourseEntryCtaData cta;
  final CourseEntryPricingData? pricing;
  final CourseEntryNextRecommendedLessonData? nextRecommendedLesson;

  factory CourseEntryViewData.fromResponse(Object? payload) {
    _rejectCourseEntryRuntimeFields(payload, 'course_entry_view');
    return CourseEntryViewData(
      course: CourseEntryCourseData.fromResponse(
        _requiredField(payload, 'course'),
      ),
      lessons: _requireList(_requiredField(payload, 'lessons'), 'lessons')
          .map(CourseEntryLessonShellData.fromResponse)
          .toList(growable: false),
      access: CourseEntryAccessData.fromResponse(
        _requiredField(payload, 'access'),
      ),
      cta: CourseEntryCtaData.fromResponse(_requiredField(payload, 'cta')),
      pricing: switch (_requiredField(payload, 'pricing')) {
        null => null,
        final Object pricing => CourseEntryPricingData.fromResponse(pricing),
      },
      nextRecommendedLesson:
          switch (_requiredField(payload, 'next_recommended_lesson')) {
            null => null,
            final Object lesson =>
              CourseEntryNextRecommendedLessonData.fromResponse(lesson),
          },
    );
  }
}

class CourseEntryCourseData {
  const CourseEntryCourseData({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.cover,
    required this.requiredEnrollmentSource,
    required this.isPremium,
    required this.priceAmountCents,
    required this.priceCurrency,
    required this.formattedPrice,
    required this.sellable,
  });

  final String id;
  final String slug;
  final String title;
  final String? description;
  final CourseEntryCoverData? cover;
  final String? requiredEnrollmentSource;
  final bool isPremium;
  final int? priceAmountCents;
  final String? priceCurrency;
  final String? formattedPrice;
  final bool sellable;

  factory CourseEntryCourseData.fromResponse(Object? payload) {
    return CourseEntryCourseData(
      id: _requireString(_requiredField(payload, 'id'), 'id'),
      slug: _requireString(_requiredField(payload, 'slug'), 'slug'),
      title: _requireString(_requiredField(payload, 'title'), 'title'),
      description: _optionalString(
        _requiredField(payload, 'description'),
        'description',
      ),
      cover: switch (_requiredField(payload, 'cover')) {
        null => null,
        final Object cover => CourseEntryCoverData.fromResponse(cover),
      },
      requiredEnrollmentSource: _optionalString(
        _requiredField(payload, 'required_enrollment_source'),
        'required_enrollment_source',
      ),
      isPremium: _requireBool(_requiredField(payload, 'is_premium'), 'is_premium'),
      priceAmountCents: _optionalInt(
        _requiredField(payload, 'price_amount_cents'),
        'price_amount_cents',
      ),
      priceCurrency: _optionalString(
        _requiredField(payload, 'price_currency'),
        'price_currency',
      ),
      formattedPrice: _optionalString(
        _requiredField(payload, 'formatted_price'),
        'formatted_price',
      ),
      sellable: _requireBool(_requiredField(payload, 'sellable'), 'sellable'),
    );
  }
}

class CourseEntryCoverData {
  const CourseEntryCoverData({required this.url, required this.alt});

  final String url;
  final String? alt;

  factory CourseEntryCoverData.fromResponse(Object? payload) {
    return CourseEntryCoverData(
      url: _requireString(_requiredField(payload, 'url'), 'url'),
      alt: _optionalString(_requiredField(payload, 'alt'), 'alt'),
    );
  }
}

class CourseEntryLessonShellData {
  const CourseEntryLessonShellData({
    required this.id,
    required this.lessonTitle,
    required this.position,
    required this.availability,
    required this.progression,
  });

  final String id;
  final String lessonTitle;
  final int position;
  final CourseEntryLessonAvailabilityData availability;
  final CourseEntryLessonProgressionData progression;

  factory CourseEntryLessonShellData.fromResponse(Object? payload) {
    return CourseEntryLessonShellData(
      id: _requireString(_requiredField(payload, 'id'), 'id'),
      lessonTitle: _requireString(
        _requiredField(payload, 'lesson_title'),
        'lesson_title',
      ),
      position: _requireInt(_requiredField(payload, 'position'), 'position'),
      availability: CourseEntryLessonAvailabilityData.fromResponse(
        _requiredField(payload, 'availability'),
      ),
      progression: CourseEntryLessonProgressionData.fromResponse(
        _requiredField(payload, 'progression'),
      ),
    );
  }
}

class CourseEntryLessonAvailabilityData {
  const CourseEntryLessonAvailabilityData({
    required this.state,
    required this.canOpen,
    required this.reasonCode,
    required this.reasonText,
    required this.nextUnlockAt,
  });

  final String state;
  final bool canOpen;
  final String? reasonCode;
  final String? reasonText;
  final DateTime? nextUnlockAt;

  factory CourseEntryLessonAvailabilityData.fromResponse(Object? payload) {
    return CourseEntryLessonAvailabilityData(
      state: _requireString(_requiredField(payload, 'state'), 'state'),
      canOpen: _requireBool(_requiredField(payload, 'can_open'), 'can_open'),
      reasonCode: _optionalString(
        _requiredField(payload, 'reason_code'),
        'reason_code',
      ),
      reasonText: _optionalString(
        _requiredField(payload, 'reason_text'),
        'reason_text',
      ),
      nextUnlockAt: _optionalDateTime(
        _requiredField(payload, 'next_unlock_at'),
        'next_unlock_at',
      ),
    );
  }
}

class CourseEntryLessonProgressionData {
  const CourseEntryLessonProgressionData({
    required this.state,
    required this.completedAt,
    required this.isNextRecommended,
  });

  final String state;
  final DateTime? completedAt;
  final bool isNextRecommended;

  factory CourseEntryLessonProgressionData.fromResponse(Object? payload) {
    return CourseEntryLessonProgressionData(
      state: _requireString(_requiredField(payload, 'state'), 'state'),
      completedAt: _optionalDateTime(
        _requiredField(payload, 'completed_at'),
        'completed_at',
      ),
      isNextRecommended: _requireBool(
        _requiredField(payload, 'is_next_recommended'),
        'is_next_recommended',
      ),
    );
  }
}

class CourseEntryAccessData {
  const CourseEntryAccessData({
    required this.isEnrolled,
    required this.isInDrip,
    required this.isInAnyIntroDrip,
    required this.canEnroll,
    required this.canPurchase,
  });

  final bool isEnrolled;
  final bool isInDrip;
  final bool isInAnyIntroDrip;
  final bool canEnroll;
  final bool canPurchase;

  factory CourseEntryAccessData.fromResponse(Object? payload) {
    return CourseEntryAccessData(
      isEnrolled: _requireBool(
        _requiredField(payload, 'is_enrolled'),
        'is_enrolled',
      ),
      isInDrip: _requireBool(_requiredField(payload, 'is_in_drip'), 'is_in_drip'),
      isInAnyIntroDrip: _requireBool(
        _requiredField(payload, 'is_in_any_intro_drip'),
        'is_in_any_intro_drip',
      ),
      canEnroll: _requireBool(_requiredField(payload, 'can_enroll'), 'can_enroll'),
      canPurchase: _requireBool(
        _requiredField(payload, 'can_purchase'),
        'can_purchase',
      ),
    );
  }
}

class CourseEntryCtaData {
  const CourseEntryCtaData({
    required this.type,
    required this.label,
    required this.enabled,
    required this.reasonCode,
    required this.reasonText,
    required this.price,
    required this.action,
  });

  final String type;
  final String label;
  final bool enabled;
  final String? reasonCode;
  final String? reasonText;
  final Map<String, Object?>? price;
  final Map<String, Object?>? action;

  String? get actionType => switch (action?['type']) {
    final String type when type.isNotEmpty => type,
    _ => null,
  };

  factory CourseEntryCtaData.fromResponse(Object? payload) {
    return CourseEntryCtaData(
      type: _requireString(_requiredField(payload, 'type'), 'type'),
      label: _requireString(_requiredField(payload, 'label'), 'label'),
      enabled: _requireBool(_requiredField(payload, 'enabled'), 'enabled'),
      reasonCode: _optionalString(
        _requiredField(payload, 'reason_code'),
        'reason_code',
      ),
      reasonText: _optionalString(
        _requiredField(payload, 'reason_text'),
        'reason_text',
      ),
      price: _optionalMap(_requiredField(payload, 'price'), 'price'),
      action: _optionalMap(_requiredField(payload, 'action'), 'action'),
    );
  }
}

class CourseEntryPricingData {
  const CourseEntryPricingData({
    required this.priceAmountCents,
    required this.priceCurrency,
    required this.formattedPrice,
    required this.sellable,
  });

  final int? priceAmountCents;
  final String? priceCurrency;
  final String? formattedPrice;
  final bool sellable;

  factory CourseEntryPricingData.fromResponse(Object? payload) {
    return CourseEntryPricingData(
      priceAmountCents: _optionalInt(
        _requiredField(payload, 'price_amount_cents'),
        'price_amount_cents',
      ),
      priceCurrency: _optionalString(
        _requiredField(payload, 'price_currency'),
        'price_currency',
      ),
      formattedPrice: _optionalString(
        _requiredField(payload, 'formatted_price'),
        'formatted_price',
      ),
      sellable: _requireBool(_requiredField(payload, 'sellable'), 'sellable'),
    );
  }
}

class CourseEntryNextRecommendedLessonData {
  const CourseEntryNextRecommendedLessonData({
    required this.id,
    required this.lessonTitle,
    required this.position,
  });

  final String id;
  final String lessonTitle;
  final int position;

  factory CourseEntryNextRecommendedLessonData.fromResponse(Object? payload) {
    return CourseEntryNextRecommendedLessonData(
      id: _requireString(_requiredField(payload, 'id'), 'id'),
      lessonTitle: _requireString(
        _requiredField(payload, 'lesson_title'),
        'lesson_title',
      ),
      position: _requireInt(_requiredField(payload, 'position'), 'position'),
    );
  }
}

class CourseDetailData {
  const CourseDetailData({
    required this.course,
    required this.lessons,
    required this.description,
  });

  final CourseSummary course;
  final List<LessonSummary> lessons;
  final String? description;

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
      description: _optionalString(
        _requiredField(payload, 'description'),
        'description',
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

class IntroSelectionStateData {
  const IntroSelectionStateData({
    required this.selectionLocked,
    required this.selectionLockReason,
    required this.eligibleCourses,
  });

  final bool selectionLocked;
  final String? selectionLockReason;
  final List<CourseSummary> eligibleCourses;

  factory IntroSelectionStateData.fromResponse(Object? payload) {
    return IntroSelectionStateData(
      selectionLocked: _requireBool(
        _requiredField(payload, 'selection_locked'),
        'selection_locked',
      ),
      selectionLockReason: _optionalString(
        _requiredField(payload, 'selection_lock_reason'),
        'selection_lock_reason',
      ),
      eligibleCourses: _requireList(
        _requiredField(payload, 'eligible_courses'),
        'eligible_courses',
      ).map(CourseSummary.fromResponse).toList(growable: false),
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
    required this.isIntroCourse,
    required this.selectionLocked,
    required this.canAccess,
    required this.enrollment,
    this.nextUnlockAt,
  });

  final String courseId;
  final int groupPosition;
  final String? requiredEnrollmentSource;
  final bool enrollable;
  final bool purchasable;
  final bool isIntroCourse;
  final bool selectionLocked;
  final bool canAccess;
  final CourseEnrollmentRecord? enrollment;
  final DateTime? nextUnlockAt;

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
      isIntroCourse: _requireBool(
        _requiredField(payload, 'is_intro_course'),
        'is_intro_course',
      ),
      selectionLocked: _requireBool(
        _requiredField(payload, 'selection_locked'),
        'selection_locked',
      ),
      canAccess: _requireBool(
        _requiredField(payload, 'can_access'),
        'can_access',
      ),
      nextUnlockAt: _optionalDateTime(
        _requiredField(payload, 'next_unlock_at'),
        'next_unlock_at',
      ),
      enrollment: enrollmentPayload == null
          ? null
          : CourseEnrollmentRecord.fromResponse(enrollmentPayload),
    );
  }
}

class CourseSummary {
  const CourseSummary({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
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
  final String? description;
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

  static const String introRequiredEnrollmentSource = 'intro';

  bool get isIntroCourse =>
      requiredEnrollmentSource == introRequiredEnrollmentSource;

  factory CourseSummary.fromResponse(Object? payload) {
    _rejectLegacyCourseCoverFields(payload, 'course');
    _rejectLegacyCourseProgressionFields(payload, 'course');
    return CourseSummary(
      id: _requireString(_requiredField(payload, 'id'), 'id'),
      slug: _requireString(_requiredField(payload, 'slug'), 'slug'),
      title: _requireString(_requiredField(payload, 'title'), 'title'),
      description: _optionalString(
        _requiredField(payload, 'description'),
        'description',
      ),
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
