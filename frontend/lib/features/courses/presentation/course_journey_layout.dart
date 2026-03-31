import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/shared/utils/course_journey_step.dart';

class CourseJourneySeriesRow {
  const CourseJourneySeriesRow({
    required this.seriesKey,
    this.step1,
    this.step2,
    this.step3,
  });

  final String seriesKey;
  final CourseSummary? step1;
  final CourseSummary? step2;
  final CourseSummary? step3;
}

List<CourseJourneySeriesRow> buildCourseJourneySeriesRows(
  Iterable<CourseSummary> courses,
) {
  final rows = <CourseJourneySeriesRow>[];
  final rowIndexBySeriesKey = <String, int>{};

  for (final course in courses) {
    final step = course.step;
    final groupId = course.courseGroupId.trim();
    if (step == CourseJourneyStep.intro || groupId.isEmpty) {
      continue;
    }

    final existingIndex = rowIndexBySeriesKey[groupId];
    if (existingIndex == null) {
      rows.add(_rowWithCourse(seriesKey: groupId, course: course, step: step));
      rowIndexBySeriesKey[groupId] = rows.length - 1;
      continue;
    }

    final existing = rows[existingIndex];
    if (_slotForStep(existing, step) == null) {
      rows[existingIndex] = _copyRowWithCourse(
        row: existing,
        course: course,
        step: step,
      );
    }
  }

  return List.unmodifiable(rows);
}

CourseJourneySeriesRow _rowWithCourse({
  required String seriesKey,
  required CourseSummary course,
  required CourseJourneyStep step,
}) {
  return switch (step) {
    CourseJourneyStep.step1 => CourseJourneySeriesRow(
      seriesKey: seriesKey,
      step1: course,
    ),
    CourseJourneyStep.step2 => CourseJourneySeriesRow(
      seriesKey: seriesKey,
      step2: course,
    ),
    CourseJourneyStep.step3 => CourseJourneySeriesRow(
      seriesKey: seriesKey,
      step3: course,
    ),
    CourseJourneyStep.intro => CourseJourneySeriesRow(seriesKey: seriesKey),
  };
}

CourseJourneySeriesRow _copyRowWithCourse({
  required CourseJourneySeriesRow row,
  required CourseSummary course,
  required CourseJourneyStep step,
}) {
  return switch (step) {
    CourseJourneyStep.step1 => CourseJourneySeriesRow(
      seriesKey: row.seriesKey,
      step1: course,
      step2: row.step2,
      step3: row.step3,
    ),
    CourseJourneyStep.step2 => CourseJourneySeriesRow(
      seriesKey: row.seriesKey,
      step1: row.step1,
      step2: course,
      step3: row.step3,
    ),
    CourseJourneyStep.step3 => CourseJourneySeriesRow(
      seriesKey: row.seriesKey,
      step1: row.step1,
      step2: row.step2,
      step3: course,
    ),
    CourseJourneyStep.intro => row,
  };
}

CourseSummary? _slotForStep(
  CourseJourneySeriesRow row,
  CourseJourneyStep step,
) {
  return switch (step) {
    CourseJourneyStep.step1 => row.step1,
    CourseJourneyStep.step2 => row.step2,
    CourseJourneyStep.step3 => row.step3,
    CourseJourneyStep.intro => null,
  };
}
