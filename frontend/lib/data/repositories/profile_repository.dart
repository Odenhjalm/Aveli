import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/data/models/profile.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final ApiClient _client;

  Future<Profile?> getMe() async {
    final data = await _client.get<Map<String, dynamic>>('/profiles/me');
    if (data.isEmpty) return null;
    return Profile.fromJson(data);
  }

  Future<Profile> updateMe({
    String? displayName,
    String? bio,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) {
      body['display_name'] = displayName;
    }
    if (bio != null) {
      body['bio'] = bio;
    }

    final data = await _client.patch<Map<String, dynamic>>(
      '/profiles/me',
      body: body.isEmpty ? null : body,
    );
    if (data == null || data.isEmpty) {
      throw StateError('Det gick inte att uppdatera profilen.');
    }
    return Profile.fromJson(data);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return ProfileRepository(client);
});
