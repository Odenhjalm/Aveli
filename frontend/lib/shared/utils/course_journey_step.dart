enum CourseJourneyStep {
  intro('intro', 'Introduktion'),
  step1('step1', 'Steg 1'),
  step2('step2', 'Steg 2'),
  step3('step3', 'Steg 3');

  const CourseJourneyStep(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static CourseJourneyStep? tryParse(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    for (final step in CourseJourneyStep.values) {
      if (step.apiValue == normalized) return step;
    }
    return null;
  }
}

