import 'package:aveli/features/courses/data/courses_repository.dart';

class LearnerCourseVisibility {
  LearnerCourseVisibility._({
    required this.course,
    required Iterable<LessonSummary> lessons,
    required this.canAccess,
    required this.currentUnlockPosition,
    required this.enrollment,
    required DateTime? nextUnlockAt,
    required DateTime now,
  }) : lessons = List.unmodifiable(lessons),
       nextUnlockAt = nextUnlockAt?.toUtc(),
       _now = now.toUtc();

  factory LearnerCourseVisibility.fromState({
    required List<LessonSummary> lessons,
    required CourseAccessData? courseState,
    CourseSummary? course,
    DateTime? now,
  }) {
    final canAccess = courseState?.canAccess == true;
    final enrollment = canAccess ? courseState?.enrollment : null;
    final currentUnlockPosition = canAccess
        ? enrollment?.currentUnlockPosition
        : null;
    return LearnerCourseVisibility._(
      course: course,
      lessons: visibleLearnerLessons(lessons),
      canAccess: canAccess,
      currentUnlockPosition: currentUnlockPosition,
      enrollment: enrollment,
      nextUnlockAt: canAccess ? courseState?.nextUnlockAt : null,
      now: now ?? DateTime.now().toUtc(),
    );
  }

  final CourseSummary? course;
  final List<LessonSummary> lessons;
  final bool canAccess;
  final int? currentUnlockPosition;
  final CourseEnrollmentRecord? enrollment;
  final DateTime? nextUnlockAt;
  final DateTime _now;

  List<LessonSummary> get unlockedLessons =>
      List.unmodifiable(lessons.where((lesson) => !isLessonLocked(lesson)));

  LessonSummary? get firstLockedLesson {
    for (final lesson in lessons) {
      if (isLessonLocked(lesson)) {
        return lesson;
      }
    }
    return null;
  }

  bool get hasVisibleLessons => lessons.isNotEmpty;

  bool get hasLockedLessons => firstLockedLesson != null;

  bool get isDripSummaryVisible {
    if (!canAccess) {
      return false;
    }
    return (course?.dripEnabled ?? false) || hasLockedLessons;
  }

  bool get showsNextLessonIndicator => canAccess && hasVisibleLessons;

  bool isLessonLocked(LessonSummary lesson) {
    final unlockPosition = currentUnlockPosition;
    if (!canAccess || unlockPosition == null) {
      return true;
    }
    return lesson.position > unlockPosition;
  }

  int? daysUntilLessonUnlock(LessonSummary lesson) {
    if (!isLessonLocked(lesson) || !_isNextLockedLesson(lesson)) {
      return null;
    }
    final unlockAt = nextUnlockAt;
    if (unlockAt == null) {
      return null;
    }
    final secondsRemaining = unlockAt.difference(_now).inSeconds;
    if (secondsRemaining <= 0) {
      return 0;
    }
    return (secondsRemaining / Duration.secondsPerDay).ceil();
  }

  String? get nextLessonIndicatorText {
    if (!showsNextLessonIndicator) {
      return null;
    }
    final nextLesson = firstLockedLesson;
    if (nextLesson == null) {
      return 'Alla lektioner tillg\u00e4ngliga';
    }
    final daysRemaining = daysUntilLessonUnlock(nextLesson);
    if (daysRemaining != null) {
      return 'N\u00e4sta lektion om ${formatDayCount(daysRemaining)}';
    }
    return 'N\u00e4sta lektion sl\u00e4pps stegvis';
  }

  String statusLabelFor(LessonSummary lesson) {
    return isLessonLocked(lesson) ? 'L\u00e5st' : 'Tillg\u00e4nglig';
  }

  String lockedLessonMessage(LessonSummary lesson) {
    final daysRemaining = daysUntilLessonUnlock(lesson);
    if (daysRemaining != null) {
      return 'Den h\u00e4r lektionen blir tillg\u00e4nglig om ${formatDayCount(daysRemaining)}';
    }
    return 'Den h\u00e4r lektionen blir tillg\u00e4nglig senare.';
  }

  bool _isNextLockedLesson(LessonSummary lesson) {
    final nextLesson = firstLockedLesson;
    if (nextLesson == null) {
      return false;
    }
    return nextLesson.id == lesson.id;
  }
}

List<LessonSummary> visibleLearnerLessons(List<LessonSummary> lessons) {
  final visible = lessons
      .where(
        (lesson) =>
            lesson.lessonTitle.isNotEmpty &&
            !lesson.lessonTitle.trim().startsWith('_'),
      )
      .toList(growable: false);
  visible.sort((a, b) => a.position.compareTo(b.position));
  return visible;
}

String formatDayCount(int days) {
  if (days == 1) {
    return '1 dag';
  }
  return '$days dagar';
}
