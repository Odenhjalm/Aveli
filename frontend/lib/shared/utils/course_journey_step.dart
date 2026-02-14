/// Placement on "Alla kurser" (journey grouping).
///
/// NOTE: This is not the same thing as whether a course is an intro course.
/// Use `is_free_intro` for the global intro vs paid course type logic.
enum CourseJourneyStep { step1, step2, step3 }

CourseJourneyStep? courseJourneyStepFromApi(Object? value) {
  if (value is num) {
    switch (value.toInt()) {
      case 1:
        return CourseJourneyStep.step1;
      case 2:
        return CourseJourneyStep.step2;
      case 3:
        return CourseJourneyStep.step3;
    }
    return null;
  }

  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case '1':
      case 'intro':
      case 'step1':
        return CourseJourneyStep.step1;
      case '2':
      case 'step2':
        return CourseJourneyStep.step2;
      case '3':
      case 'step3':
        return CourseJourneyStep.step3;
    }
  }

  return null;
}

extension CourseJourneyStepApiValue on CourseJourneyStep {
  int get apiValue {
    switch (this) {
      case CourseJourneyStep.step1:
        return 1;
      case CourseJourneyStep.step2:
        return 2;
      case CourseJourneyStep.step3:
        return 3;
    }
  }

  String get label {
    switch (this) {
      case CourseJourneyStep.step1:
        return 'Steg 1';
      case CourseJourneyStep.step2:
        return 'Steg 2';
      case CourseJourneyStep.step3:
        return 'Steg 3';
    }
  }
}
