import 'dart:math' as math;

import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/shared/utils/course_journey_step.dart';

class CourseJourneyRow {
  const CourseJourneyRow({this.step1, this.step2, this.step3});

  final CourseSummary? step1;
  final CourseSummary? step2;
  final CourseSummary? step3;
}

List<CourseJourneyRow> buildCourseJourneyRows(Iterable<CourseSummary> courses) {
  final seriesOrder = <String>[];
  final seriesBuckets = <String, _JourneySeriesBucket>{};

  for (final course in courses) {
    final step = course.journeyStep;
    if (step == null || step == CourseJourneyStep.intro) {
      continue;
    }

    final seriesKey = _seriesKeyForCourse(course);
    final bucket = seriesBuckets.putIfAbsent(seriesKey, () {
      seriesOrder.add(seriesKey);
      return _JourneySeriesBucket();
    });
    bucket.add(step, course);
  }

  final rows = <CourseJourneyRow>[];
  for (final seriesKey in seriesOrder) {
    final bucket = seriesBuckets[seriesKey]!;
    final rowCount = math.max(
      bucket.step1Courses.length,
      math.max(bucket.step2Courses.length, bucket.step3Courses.length),
    );
    for (var index = 0; index < rowCount; index += 1) {
      rows.add(
        CourseJourneyRow(
          step1: bucket.courseAt(CourseJourneyStep.step1, index),
          step2: bucket.courseAt(CourseJourneyStep.step2, index),
          step3: bucket.courseAt(CourseJourneyStep.step3, index),
        ),
      );
    }
  }

  return List.unmodifiable(rows);
}

class _JourneySeriesBucket {
  final step1Courses = <CourseSummary>[];
  final step2Courses = <CourseSummary>[];
  final step3Courses = <CourseSummary>[];

  void add(CourseJourneyStep step, CourseSummary course) {
    switch (step) {
      case CourseJourneyStep.step1:
        step1Courses.add(course);
        break;
      case CourseJourneyStep.step2:
        step2Courses.add(course);
        break;
      case CourseJourneyStep.step3:
        step3Courses.add(course);
        break;
      case CourseJourneyStep.intro:
        break;
    }
  }

  CourseSummary? courseAt(CourseJourneyStep step, int index) {
    final courses = switch (step) {
      CourseJourneyStep.step1 => step1Courses,
      CourseJourneyStep.step2 => step2Courses,
      CourseJourneyStep.step3 => step3Courses,
      CourseJourneyStep.intro => const <CourseSummary>[],
    };
    return index < courses.length ? courses[index] : null;
  }
}

String _seriesKeyForCourse(CourseSummary course) {
  final branch = _normalizeSeriesToken(course.branch);
  if (branch != null) {
    return 'branch:$branch';
  }

  final slug = _normalizeSeriesToken(course.slug);
  final courseFamily = _normalizeSeriesToken(course.courseFamily);
  if (courseFamily != null && courseFamily != slug) {
    return 'family:$courseFamily';
  }

  final step = course.journeyStep;
  if (step != null) {
    final slugSeries = _stripJourneyStepMarker(course.slug, step);
    if (slugSeries != null) {
      return 'slug:$slugSeries';
    }

    final titleSeries = _stripJourneyStepMarker(course.title, step);
    if (titleSeries != null) {
      return 'title:$titleSeries';
    }
  }

  if (courseFamily != null) {
    return 'family:$courseFamily';
  }
  if (slug != null) {
    return 'course:$slug';
  }
  return 'course:${course.id}';
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

  final suffix = RegExp('^(.*?)-(?:steg|step|del)-?$stepNumber\$');
  final suffixMatch = suffix.firstMatch(normalized);
  if (suffixMatch != null) {
    return _cleanSeriesRoot(suffixMatch.group(1));
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
