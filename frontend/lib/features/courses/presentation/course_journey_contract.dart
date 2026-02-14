import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/shared/utils/course_journey_step.dart';

enum JourneyContractIssueCode {
  missingJourneyGroupId,
  invalidJourneyStep,
  duplicateJourneyStep,
}

class JourneyContractIssue {
  const JourneyContractIssue({
    required this.code,
    required this.courseId,
    this.journeyGroupId,
  });

  final JourneyContractIssueCode code;
  final String courseId;
  final String? journeyGroupId;
}

class CourseJourneyRow {
  const CourseJourneyRow({
    required this.journeyGroupId,
    required this.step1,
    required this.step2,
    required this.step3,
  });

  final String journeyGroupId;
  final CourseSummary? step1;
  final CourseSummary? step2;
  final CourseSummary? step3;

  bool get isComplete => step1 != null && step2 != null && step3 != null;
}

class CourseJourneyContract {
  const CourseJourneyContract({required this.rows, required this.issues});

  final List<CourseJourneyRow> rows;
  final List<JourneyContractIssue> issues;
}

CourseJourneyContract buildCourseJourneyContract(
  Iterable<CourseSummary> courses,
) {
  final grouped = <String, Map<CourseJourneyStep, CourseSummary>>{};
  final issues = <JourneyContractIssue>[];

  for (final course in courses) {
    final groupId = (course.journeyGroupId ?? '').trim();
    if (groupId.isEmpty) {
      issues.add(
        JourneyContractIssue(
          code: JourneyContractIssueCode.missingJourneyGroupId,
          courseId: course.id,
        ),
      );
      continue;
    }

    final step = course.journeyStep;
    if (step == null) {
      issues.add(
        JourneyContractIssue(
          code: JourneyContractIssueCode.invalidJourneyStep,
          courseId: course.id,
          journeyGroupId: groupId,
        ),
      );
      continue;
    }

    final stepMap = grouped.putIfAbsent(
      groupId,
      () => <CourseJourneyStep, CourseSummary>{},
    );

    if (stepMap.containsKey(step)) {
      issues.add(
        JourneyContractIssue(
          code: JourneyContractIssueCode.duplicateJourneyStep,
          courseId: course.id,
          journeyGroupId: groupId,
        ),
      );
      continue;
    }

    stepMap[step] = course;
  }

  final rows = grouped.entries
      .map(
        (entry) => CourseJourneyRow(
          journeyGroupId: entry.key,
          step1: entry.value[CourseJourneyStep.step1],
          step2: entry.value[CourseJourneyStep.step2],
          step3: entry.value[CourseJourneyStep.step3],
        ),
      )
      .toList(growable: false);

  return CourseJourneyContract(rows: rows, issues: List.unmodifiable(issues));
}
