import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_journey_contract.dart';
import 'package:aveli/shared/utils/course_journey_step.dart';

void main() {
  test('groups courses by journey_group_id and preserves missing steps', () {
    final contract = buildCourseJourneyContract([
      const CourseSummary(
        id: 'course-1',
        slug: 'course-1',
        title: 'Course 1',
        journeyGroupId: 'alpha',
        journeyStep: CourseJourneyStep.step1,
      ),
      const CourseSummary(
        id: 'course-2',
        slug: 'course-2',
        title: 'Course 2',
        journeyGroupId: 'alpha',
        journeyStep: CourseJourneyStep.step3,
      ),
      const CourseSummary(
        id: 'course-3',
        slug: 'course-3',
        title: 'Course 3',
        journeyGroupId: 'beta',
        journeyStep: CourseJourneyStep.step2,
      ),
    ]);

    expect(contract.issues, isEmpty);
    expect(contract.rows, hasLength(2));

    final alpha = contract.rows.first;
    expect(alpha.journeyGroupId, 'alpha');
    expect(alpha.step1?.id, 'course-1');
    expect(alpha.step2, isNull);
    expect(alpha.step3?.id, 'course-2');
    expect(alpha.isComplete, isFalse);

    final beta = contract.rows.last;
    expect(beta.journeyGroupId, 'beta');
    expect(beta.step1, isNull);
    expect(beta.step2?.id, 'course-3');
    expect(beta.step3, isNull);
    expect(beta.isComplete, isFalse);
  });

  test('flags invalid and duplicate journey assignments', () {
    final contract = buildCourseJourneyContract([
      const CourseSummary(
        id: 'missing-group',
        slug: 'missing-group',
        title: 'Missing Group',
        journeyStep: CourseJourneyStep.step1,
      ),
      const CourseSummary(
        id: 'invalid-step',
        slug: 'invalid-step',
        title: 'Invalid Step',
        journeyGroupId: 'alpha',
      ),
      const CourseSummary(
        id: 'alpha-step-1-primary',
        slug: 'alpha-step-1-primary',
        title: 'Primary Step',
        journeyGroupId: 'alpha',
        journeyStep: CourseJourneyStep.step1,
      ),
      const CourseSummary(
        id: 'alpha-step-1-duplicate',
        slug: 'alpha-step-1-duplicate',
        title: 'Duplicate Step',
        journeyGroupId: 'alpha',
        journeyStep: CourseJourneyStep.step1,
      ),
    ]);

    expect(contract.issues, hasLength(3));
    expect(
      contract.issues.where(
        (issue) => issue.code == JourneyContractIssueCode.missingJourneyGroupId,
      ),
      hasLength(1),
    );
    expect(
      contract.issues.where(
        (issue) => issue.code == JourneyContractIssueCode.invalidJourneyStep,
      ),
      hasLength(1),
    );
    expect(
      contract.issues.where(
        (issue) => issue.code == JourneyContractIssueCode.duplicateJourneyStep,
      ),
      hasLength(1),
    );

    expect(contract.rows, hasLength(1));
    final alpha = contract.rows.single;
    expect(alpha.journeyGroupId, 'alpha');
    expect(alpha.step1?.id, 'alpha-step-1-primary');
  });
}
