import 'package:aveli/features/courses/data/courses_repository.dart';

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
    final groupPosition = course.groupPosition;
    final groupId = course.courseGroupId.trim();
    if (groupPosition == 0 || groupId.isEmpty) {
      continue;
    }

    final existingIndex = rowIndexBySeriesKey[groupId];
    if (existingIndex == null) {
      rows.add(_rowWithCourse(
        seriesKey: groupId,
        course: course,
        groupPosition: groupPosition,
      ));
      rowIndexBySeriesKey[groupId] = rows.length - 1;
      continue;
    }

    final existing = rows[existingIndex];
    if (_slotForGroupPosition(existing, groupPosition) == null) {
      rows[existingIndex] = _copyRowWithCourse(
        row: existing,
        course: course,
        groupPosition: groupPosition,
      );
    }
  }

  return List.unmodifiable(rows);
}

CourseJourneySeriesRow _rowWithCourse({
  required String seriesKey,
  required CourseSummary course,
  required int groupPosition,
}) {
  return switch (groupPosition) {
    1 => CourseJourneySeriesRow(
      seriesKey: seriesKey,
      step1: course,
    ),
    2 => CourseJourneySeriesRow(
      seriesKey: seriesKey,
      step2: course,
    ),
    3 => CourseJourneySeriesRow(
      seriesKey: seriesKey,
      step3: course,
    ),
    _ => CourseJourneySeriesRow(seriesKey: seriesKey),
  };
}

CourseJourneySeriesRow _copyRowWithCourse({
  required CourseJourneySeriesRow row,
  required CourseSummary course,
  required int groupPosition,
}) {
  return switch (groupPosition) {
    1 => CourseJourneySeriesRow(
      seriesKey: row.seriesKey,
      step1: course,
      step2: row.step2,
      step3: row.step3,
    ),
    2 => CourseJourneySeriesRow(
      seriesKey: row.seriesKey,
      step1: row.step1,
      step2: course,
      step3: row.step3,
    ),
    3 => CourseJourneySeriesRow(
      seriesKey: row.seriesKey,
      step1: row.step1,
      step2: row.step2,
      step3: course,
    ),
    _ => row,
  };
}

CourseSummary? _slotForGroupPosition(
  CourseJourneySeriesRow row,
  int groupPosition,
) {
  return switch (groupPosition) {
    1 => row.step1,
    2 => row.step2,
    3 => row.step3,
    _ => null,
  };
}
