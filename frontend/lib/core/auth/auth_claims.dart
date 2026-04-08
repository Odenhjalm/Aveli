import 'dart:convert';

import 'package:aveli/data/models/profile.dart';

class AuthClaims {
  const AuthClaims({
    required this.role,
    required this.isAdmin,
    this.onboardingState,
  });

  final String role;
  final bool isAdmin;
  final String? onboardingState;

  UserRole get userRole => parseUserRole(role);
  bool get isTeacher => userRole == UserRole.teacher;

  factory AuthClaims.fromMap(Map<String, dynamic> payload) {
    final normalizedRole = parseUserRole(payload['role'] as String?);
    final admin = payload['is_admin'] == true;
    final rawOnboardingState = payload['onboarding_state'] as String?;
    final onboardingState =
        rawOnboardingState == OnboardingStateValue.incomplete ||
            rawOnboardingState == OnboardingStateValue.completed
        ? rawOnboardingState
        : null;
    return AuthClaims(
      role: normalizedRole == UserRole.teacher ? 'teacher' : 'learner',
      isAdmin: admin,
      onboardingState: onboardingState,
    );
  }

  static AuthClaims? fromToken(String token) {
    final payload = _decodePayload(token);
    if (payload == null) {
      return null;
    }
    return AuthClaims.fromMap(payload);
  }

  static Map<String, dynamic>? _decodePayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return null;
    }
    try {
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final data = json.decode(decoded);
      if (data is Map<String, dynamic>) {
        return data;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
