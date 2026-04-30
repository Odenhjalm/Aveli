import 'package:equatable/equatable.dart';

import 'package:aveli/api/api_client.dart';

class HomeEntryViewPayload extends Equatable {
  const HomeEntryViewPayload({required this.ongoingCourses});

  factory HomeEntryViewPayload.fromJson(Map<String, dynamic> json) {
    final items = _requiredList(json['ongoing_courses'], 'ongoing_courses');
    return HomeEntryViewPayload(
      ongoingCourses: items
          .map(HomeEntryOngoingCourse.fromJson)
          .toList(growable: false),
    );
  }

  final List<HomeEntryOngoingCourse> ongoingCourses;

  @override
  List<Object?> get props => [ongoingCourses];
}

class HomeEntryOngoingCourse extends Equatable {
  const HomeEntryOngoingCourse({
    required this.courseId,
    required this.slug,
    required this.title,
    required this.coverMedia,
    required this.progress,
    required this.nextLesson,
    required this.cta,
    required this.status,
  });

  factory HomeEntryOngoingCourse.fromJson(Map<String, dynamic> json) {
    return HomeEntryOngoingCourse(
      courseId: _requiredString(json['course_id'], 'course_id'),
      slug: _requiredString(json['slug'], 'slug'),
      title: _requiredString(json['title'], 'title'),
      coverMedia: HomeEntryCoverMedia.fromJson(
        _requiredMap(json['cover_media'], 'cover_media'),
      ),
      progress: HomeEntryProgress.fromJson(
        _requiredMap(json['progress'], 'progress'),
      ),
      nextLesson: HomeEntryNextLesson.fromJson(
        _requiredMap(json['next_lesson'], 'next_lesson'),
      ),
      cta: HomeEntryCta.fromJson(_requiredMap(json['cta'], 'cta')),
      status: HomeEntryStatus.fromJson(_requiredMap(json['status'], 'status')),
    );
  }

  final String courseId;
  final String slug;
  final String title;
  final HomeEntryCoverMedia coverMedia;
  final HomeEntryProgress progress;
  final HomeEntryNextLesson nextLesson;
  final HomeEntryCta cta;
  final HomeEntryStatus status;

  @override
  List<Object?> get props => [
    courseId,
    slug,
    title,
    coverMedia,
    progress,
    nextLesson,
    cta,
    status,
  ];
}

class HomeEntryCoverMedia extends Equatable {
  const HomeEntryCoverMedia({
    required this.mediaId,
    required this.state,
    required this.resolvedUrl,
  });

  factory HomeEntryCoverMedia.fromJson(Map<String, dynamic> json) {
    return HomeEntryCoverMedia(
      mediaId: _optionalString(json['media_id'], 'media_id'),
      state: _requiredString(json['state'], 'state'),
      resolvedUrl: _optionalString(json['resolved_url'], 'resolved_url'),
    );
  }

  final String? mediaId;
  final String state;
  final String? resolvedUrl;

  @override
  List<Object?> get props => [mediaId, state, resolvedUrl];
}

class HomeEntryProgress extends Equatable {
  const HomeEntryProgress({
    required this.state,
    required this.completedLessonCount,
    required this.totalLessonCount,
    required this.availableLessonCount,
    required this.percent,
    required this.lastActivityAt,
  });

  factory HomeEntryProgress.fromJson(Map<String, dynamic> json) {
    return HomeEntryProgress(
      state: _requiredString(json['state'], 'state'),
      completedLessonCount: _requiredInt(
        json['completed_lesson_count'],
        'completed_lesson_count',
      ),
      totalLessonCount: _requiredInt(
        json['total_lesson_count'],
        'total_lesson_count',
      ),
      availableLessonCount: _requiredInt(
        json['available_lesson_count'],
        'available_lesson_count',
      ),
      percent: _requiredDouble(json['percent'], 'percent'),
      lastActivityAt: _optionalDateTime(
        json['last_activity_at'],
        'last_activity_at',
      ),
    );
  }

  final String state;
  final int completedLessonCount;
  final int totalLessonCount;
  final int availableLessonCount;
  final double percent;
  final DateTime? lastActivityAt;

  @override
  List<Object?> get props => [
    state,
    completedLessonCount,
    totalLessonCount,
    availableLessonCount,
    percent,
    lastActivityAt,
  ];
}

class HomeEntryNextLesson extends Equatable {
  const HomeEntryNextLesson({
    required this.id,
    required this.lessonTitle,
    required this.position,
  });

  factory HomeEntryNextLesson.fromJson(Map<String, dynamic> json) {
    return HomeEntryNextLesson(
      id: _requiredString(json['id'], 'id'),
      lessonTitle: _requiredString(json['lesson_title'], 'lesson_title'),
      position: _requiredInt(json['position'], 'position'),
    );
  }

  final String id;
  final String lessonTitle;
  final int position;

  @override
  List<Object?> get props => [id, lessonTitle, position];
}

class HomeEntryCtaAction extends Equatable {
  const HomeEntryCtaAction({required this.type, required this.lessonId});

  factory HomeEntryCtaAction.fromJson(Map<String, dynamic> json) {
    return HomeEntryCtaAction(
      type: _requiredString(json['type'], 'type'),
      lessonId: _requiredString(json['lesson_id'], 'lesson_id'),
    );
  }

  final String type;
  final String lessonId;

  @override
  List<Object?> get props => [type, lessonId];
}

class HomeEntryCta extends Equatable {
  const HomeEntryCta({
    required this.type,
    required this.label,
    required this.enabled,
    required this.action,
    required this.reasonCode,
    required this.reasonText,
  });

  factory HomeEntryCta.fromJson(Map<String, dynamic> json) {
    final action = json['action'];
    return HomeEntryCta(
      type: _requiredString(json['type'], 'type'),
      label: _requiredString(json['label'], 'label'),
      enabled: _requiredBool(json['enabled'], 'enabled'),
      action: action == null
          ? null
          : HomeEntryCtaAction.fromJson(_requiredMap(action, 'action')),
      reasonCode: _optionalString(json['reason_code'], 'reason_code'),
      reasonText: _optionalString(json['reason_text'], 'reason_text'),
    );
  }

  final String type;
  final String label;
  final bool enabled;
  final HomeEntryCtaAction? action;
  final String? reasonCode;
  final String? reasonText;

  @override
  List<Object?> get props => [
    type,
    label,
    enabled,
    action,
    reasonCode,
    reasonText,
  ];
}

class HomeEntryStatus extends Equatable {
  const HomeEntryStatus({required this.eligibility, required this.reasonCode});

  factory HomeEntryStatus.fromJson(Map<String, dynamic> json) {
    return HomeEntryStatus(
      eligibility: _requiredString(json['eligibility'], 'eligibility'),
      reasonCode: _optionalString(json['reason_code'], 'reason_code'),
    );
  }

  final String eligibility;
  final String? reasonCode;

  @override
  List<Object?> get props => [eligibility, reasonCode];
}

class HomeEntryViewRepository {
  HomeEntryViewRepository(this._client);

  final ApiClient _client;

  Future<HomeEntryViewPayload> fetchHomeEntryView() async {
    final response = await _client.raw.get<Object?>('/home/entry-view');
    return HomeEntryViewPayload.fromJson(
      _requiredMap(response.data, 'home_entry_view'),
    );
  }
}

List<Map<String, dynamic>> _requiredList(Object? value, String fieldName) {
  if (value is List) {
    return value
        .map((item) => _requiredMap(item, fieldName))
        .toList(growable: false);
  }
  throw StateError('Invalid $fieldName payload');
}

Map<String, dynamic> _requiredMap(Object? value, String fieldName) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw StateError('Invalid $fieldName payload');
}

String _requiredString(Object? value, String fieldName) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw StateError('Invalid $fieldName payload');
}

String? _optionalString(Object? value, String fieldName) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw StateError('Invalid $fieldName payload');
}

int _requiredInt(Object? value, String fieldName) {
  if (value is int) {
    return value;
  }
  throw StateError('Invalid $fieldName payload');
}

double _requiredDouble(Object? value, String fieldName) {
  if (value is num) {
    return value.toDouble();
  }
  throw StateError('Invalid $fieldName payload');
}

bool _requiredBool(Object? value, String fieldName) {
  if (value is bool) {
    return value;
  }
  throw StateError('Invalid $fieldName payload');
}

DateTime? _optionalDateTime(Object? value, String fieldName) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return DateTime.parse(value);
  }
  throw StateError('Invalid $fieldName payload');
}
