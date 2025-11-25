import 'dart:convert';

import 'package:wisdom/data/models/profile.dart';

class AuthClaims {
  const AuthClaims({
    required this.role,
    required this.isTeacher,
    required this.isAdmin,
  });

  final String role;
  final bool isTeacher;
  final bool isAdmin;

  UserRole get userRole => isAdmin ? UserRole.teacher : parseUserRole(role);

  factory AuthClaims.fromMap(Map<String, dynamic> payload) {
    final rawRole = (payload['role'] as String?) ?? 'user';
    final admin = payload['is_admin'] == true;
    final teacher = payload['is_teacher'] == true || admin;
    return AuthClaims(role: rawRole, isTeacher: teacher, isAdmin: admin);
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
