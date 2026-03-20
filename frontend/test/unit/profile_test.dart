import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/data/models/profile.dart';

void main() {
  test('Profile respects backend-computed teacher access', () {
    final profile = Profile.fromJson({
      'user_id': 'teacher-1',
      'email': 'teacher@example.com',
      'role_v2': 'user',
      'is_admin': false,
      'is_teacher': true,
      'membership_active': false,
      'email_verified': true,
      'created_at': '2024-01-01T00:00:00Z',
      'updated_at': '2024-01-02T00:00:00Z',
    });

    expect(profile.userRole, UserRole.user);
    expect(profile.isTeacher, isTrue);
    expect(profile.isProfessional, isTrue);
  });
}
