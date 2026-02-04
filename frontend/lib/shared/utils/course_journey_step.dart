/// Placement on "Alla kurser" (journey grouping).
///
/// NOTE: This is not the same thing as whether a course is an intro course.
/// Use `is_free_intro` for the global intro vs paid course type logic.
enum CourseJourneyStep { intro, step1, step2, step3 }

CourseJourneyStep? courseJourneyStepFromApi(String? value) {
  switch (value) {
    case 'intro':
      return CourseJourneyStep.intro;
    case 'step1':
      return CourseJourneyStep.step1;
    case 'step2':
      return CourseJourneyStep.step2;
    case 'step3':
      return CourseJourneyStep.step3;
  }
  return null;
}

extension CourseJourneyStepApiValue on CourseJourneyStep {
  String get apiValue {
    switch (this) {
      case CourseJourneyStep.intro:
        return 'intro';
      case CourseJourneyStep.step1:
        return 'step1';
      case CourseJourneyStep.step2:
        return 'step2';
      case CourseJourneyStep.step3:
        return 'step3';
    }
  }

  String get label {
    switch (this) {
      case CourseJourneyStep.intro:
        return 'Introduktion';
      case CourseJourneyStep.step1:
        return 'Steg 1';
      case CourseJourneyStep.step2:
        return 'Steg 2';
      case CourseJourneyStep.step3:
        return 'Steg 3';
    }
  }
}
