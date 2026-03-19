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
    final step = course.journeyStep ?? course.stepLevel;
    if (step == null || step == CourseJourneyStep.intro) {
      continue;
    }

    final seriesKey = _seriesKeyForCourse(course);
    final existingIndex = rowIndexBySeriesKey[seriesKey];

    if (existingIndex == null) {
      rows.add(
        _rowWithCourse(seriesKey: seriesKey, course: course, step: step),
      );
      rowIndexBySeriesKey[seriesKey] = rows.length - 1;
      continue;
    }

    final existing = rows[existingIndex];
    if (_slotForStep(existing, step) == null) {
      rows[existingIndex] = _copyRowWithCourse(
        row: existing,
        course: course,
        step: step,
      );
      continue;
    }

    assert(() {
      final courseId = course.id;
      final occupiedId = _slotForStep(existing, step)?.id;
      // Duplicate step data for one series would otherwise collapse multiple
      // courses into the same 3-slot row, so we keep the first and log it.
      // ignore: avoid_print
      print(
        'Course journey duplicate step ignored for series "$seriesKey": '
        'kept=$occupiedId ignored=$courseId step=${step.name}',
      );
      return true;
    }());
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

String _seriesKeyForCourse(CourseSummary course) {
  final step = course.journeyStep ?? course.stepLevel;
  final derivedSeriesRoot = _derivedSeriesRoot(course, step);
  if (derivedSeriesRoot != null) {
    return 'series:$derivedSeriesRoot';
  }

  final branch = _normalizeSeriesToken(course.branch);
  if (branch != null) {
    return 'branch:$branch';
  }

  final slug = _normalizeSeriesToken(course.slug);
  if (slug != null) {
    return 'course:$slug';
  }
  return 'course:${course.id}';
}

String? _derivedSeriesRoot(CourseSummary course, CourseJourneyStep? step) {
  final courseFamily = _normalizeSeriesRoot(course.courseFamily, step);
  if (courseFamily != null) {
    return courseFamily;
  }

  if (step == null) {
    return null;
  }

  final titleSeries = _stripJourneyStepMarker(course.title, step);
  if (titleSeries != null) {
    return titleSeries;
  }

  final slugSeries = _stripJourneyStepMarker(course.slug, step);
  if (slugSeries != null) {
    return slugSeries;
  }

  return null;
}

String? _normalizeSeriesRoot(String? rawValue, CourseJourneyStep? step) {
  if (step != null) {
    final stripped = _stripJourneyStepMarker(rawValue, step);
    if (stripped != null) {
      return stripped;
    }
  }
  return _normalizeSeriesToken(rawValue);
}

String? _stripJourneyStepMarker(String? rawValue, CourseJourneyStep step) {
  final normalized = _normalizeSeriesToken(rawValue);
  if (normalized == null) {
    return null;
  }

  final stepNumber = switch (step) {
    CourseJourneyStep.step1 => '1',
    CourseJourneyStep.step2 => '2',
    CourseJourneyStep.step3 => '3',
    CourseJourneyStep.intro => null,
  };
  if (stepNumber == null) {
    return null;
  }

  final infix = RegExp(
    '^(.*?)-(?:steg|step|del)-?$stepNumber(?:-|\\b).*\$',
  );
  final infixMatch = infix.firstMatch(normalized);
  if (infixMatch != null) {
    return _cleanSeriesRoot(infixMatch.group(1));
  }

  final prefix = RegExp('^(?:steg|step|del)-?$stepNumber-(.*)\$');
  final prefixMatch = prefix.firstMatch(normalized);
  if (prefixMatch != null) {
    return _cleanSeriesRoot(prefixMatch.group(1));
  }

  return null;
}

String? _cleanSeriesRoot(String? rawValue) {
  final cleaned = _normalizeSeriesToken(rawValue);
  if (cleaned == null || cleaned.isEmpty) {
    return null;
  }
  return cleaned;
}

String? _normalizeSeriesToken(String? rawValue) {
  final raw = rawValue?.trim().toLowerCase();
  if (raw == null || raw.isEmpty) {
    return null;
  }

  final normalized = raw
      .replaceAll(RegExp(r'[^0-9a-zåäö]+', caseSensitive: false), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return normalized.isEmpty ? null : normalized;
}
