enum OnboardingStateValue {
  registeredUnverified,
  verifiedUnpaid,
  paidProfileIncomplete,
  paidProfileCompleteIntroUnselected,
  paidProfileCompleteIntroSelected,
  onboardingComplete,
}

OnboardingStateValue parseOnboardingState(String? raw) {
  switch ((raw ?? '').trim()) {
    case 'registered_unverified':
      return OnboardingStateValue.registeredUnverified;
    case 'verified_unpaid':
      return OnboardingStateValue.verifiedUnpaid;
    case 'paid_profile_incomplete':
      return OnboardingStateValue.paidProfileIncomplete;
    case 'paid_profile_complete_intro_unselected':
      return OnboardingStateValue.paidProfileCompleteIntroUnselected;
    case 'paid_profile_complete_intro_selected':
      return OnboardingStateValue.paidProfileCompleteIntroSelected;
    case 'onboarding_complete':
      return OnboardingStateValue.onboardingComplete;
    default:
      return OnboardingStateValue.registeredUnverified;
  }
}

class OnboardingStatus {
  const OnboardingStatus({
    required this.onboardingState,
    required this.nextStep,
    required this.emailVerified,
    required this.membershipActive,
    required this.profileComplete,
    required this.introCourseSelected,
    required this.onboardingComplete,
    this.missingProfileFields = const [],
    this.selectedIntroCourseId,
    this.billingPending = false,
  });

  final OnboardingStateValue onboardingState;
  final String nextStep;
  final bool emailVerified;
  final bool membershipActive;
  final bool profileComplete;
  final bool introCourseSelected;
  final bool onboardingComplete;
  final List<String> missingProfileFields;
  final String? selectedIntroCourseId;
  final bool billingPending;

  factory OnboardingStatus.fromJson(Map<String, dynamic> json) {
    final missing = (json['missing_profile_fields'] as List? ?? const [])
        .map((item) => item.toString())
        .toList(growable: false);
    return OnboardingStatus(
      onboardingState: parseOnboardingState(
        json['onboarding_state']?.toString(),
      ),
      nextStep: json['next_step']?.toString() ?? '/verify',
      emailVerified: json['email_verified'] == true,
      membershipActive: json['membership_active'] == true,
      profileComplete: json['profile_complete'] == true,
      introCourseSelected: json['intro_course_selected'] == true,
      onboardingComplete: json['onboarding_complete'] == true,
      missingProfileFields: missing,
      selectedIntroCourseId: json['selected_intro_course_id']?.toString(),
      billingPending: json['billing_pending'] == true,
    );
  }
}
