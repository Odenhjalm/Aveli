import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/data/models/profile.dart';

void main() {
  test('Profile parses canonical current-profile payload as projection-only data', () {
    final profile = Profile.fromJson({
      'user_id': 'teacher-1',
      'email': 'teacher@example.com',
      'display_name': 'Teacher',
      'bio': 'Bio',
      'photo_url': 'https://example.com/avatar.jpg',
      'avatar_media_id': 'media-1',
      'created_at': '2024-01-01T00:00:00Z',
      'updated_at': '2024-01-02T00:00:00Z',
    });

    expect(profile.userRole, UserRole.learner);
    expect(profile.isTeacher, isFalse);
    expect(profile.isAdmin, isFalse);
    expect(profile.onboardingState, OnboardingStateValue.incomplete);
    expect(profile.displayName, 'Teacher');
    expect(profile.avatarMediaId, 'media-1');
  });
}
