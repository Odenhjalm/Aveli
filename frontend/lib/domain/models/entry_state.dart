import 'package:flutter/foundation.dart';

abstract final class EntryOnboardingState {
  static const incomplete = 'incomplete';
  static const welcomePending = 'welcome_pending';
  static const completed = 'completed';

  static const allowed = {incomplete, welcomePending, completed};

  static String parse(Object? value) {
    if (value is! String) {
      throw const FormatException(
        'entry_state.onboarding_state must be a string',
      );
    }
    final normalized = value.trim();
    if (!allowed.contains(normalized)) {
      throw const FormatException(
        'entry_state.onboarding_state must be canonical',
      );
    }
    return normalized;
  }
}

@immutable
class EntryState {
  const EntryState({
    required this.canEnterApp,
    required this.onboardingState,
    required this.onboardingCompleted,
    required this.membershipActive,
    required this.needsOnboarding,
    required this.needsPayment,
    required this.roleV2,
    required this.role,
    required this.isAdmin,
  });

  factory EntryState.fromJson(Map<String, dynamic> json) {
    return EntryState(
      canEnterApp: _readBool(json, 'can_enter_app'),
      onboardingState: EntryOnboardingState.parse(json['onboarding_state']),
      onboardingCompleted: _readBool(json, 'onboarding_completed'),
      membershipActive: _readBool(json, 'membership_active'),
      needsOnboarding: _readBool(json, 'needs_onboarding'),
      needsPayment: _readBool(json, 'needs_payment'),
      roleV2: _readString(json, 'role_v2'),
      role: _readString(json, 'role'),
      isAdmin: _readBool(json, 'is_admin'),
    );
  }

  final bool canEnterApp;
  final String onboardingState;
  final bool onboardingCompleted;
  final bool membershipActive;
  final bool needsOnboarding;
  final bool needsPayment;
  final String roleV2;
  final String role;
  final bool isAdmin;

  Map<String, dynamic> toJson() => {
    'can_enter_app': canEnterApp,
    'onboarding_state': onboardingState,
    'onboarding_completed': onboardingCompleted,
    'membership_active': membershipActive,
    'needs_onboarding': needsOnboarding,
    'needs_payment': needsPayment,
    'role_v2': roleV2,
    'role': role,
    'is_admin': isAdmin,
  };

  static bool _readBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    throw FormatException('entry_state.$key must be a bool');
  }

  static String _readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    throw FormatException('entry_state.$key must be a string');
  }
}
