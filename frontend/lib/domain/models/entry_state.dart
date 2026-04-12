import 'package:flutter/foundation.dart';

@immutable
class EntryState {
  const EntryState({
    required this.canEnterApp,
    required this.onboardingCompleted,
    required this.membershipActive,
    required this.needsOnboarding,
    required this.needsPayment,
    required this.isInvite,
  });

  factory EntryState.fromJson(Map<String, dynamic> json) {
    return EntryState(
      canEnterApp: _readBool(json, 'can_enter_app'),
      onboardingCompleted: _readBool(json, 'onboarding_completed'),
      membershipActive: _readBool(json, 'membership_active'),
      needsOnboarding: _readBool(json, 'needs_onboarding'),
      needsPayment: _readBool(json, 'needs_payment'),
      isInvite: _readBool(json, 'is_invite'),
    );
  }

  final bool canEnterApp;
  final bool onboardingCompleted;
  final bool membershipActive;
  final bool needsOnboarding;
  final bool needsPayment;
  final bool isInvite;

  Map<String, dynamic> toJson() => {
    'can_enter_app': canEnterApp,
    'onboarding_completed': onboardingCompleted,
    'membership_active': membershipActive,
    'needs_onboarding': needsOnboarding,
    'needs_payment': needsPayment,
    'is_invite': isInvite,
  };

  static bool _readBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    throw FormatException('entry_state.$key must be a bool');
  }
}
