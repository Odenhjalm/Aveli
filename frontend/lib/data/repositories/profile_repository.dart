import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

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

  Future<Profile> uploadAvatar({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    final multipart = MultipartFile.fromBytes(
      bytes,
      filename: filename,
      contentType: MediaType.parse(contentType),
    );
    final formData = FormData.fromMap({'file': multipart});

    final data = await _client.postForm<Map<String, dynamic>>(
      '/profiles/me/avatar',
      formData,
    );
    if (data == null || data.isEmpty) {
      throw StateError('Det gick inte att ladda upp profilbilden.');
    }
    return Profile.fromJson(data);
  }

  Future<Profile> clearAvatar() async {
    final data = await _client.delete<Map<String, dynamic>>('/profiles/me/avatar');
    if (data == null || data.isEmpty) {
      throw StateError('Det gick inte att ta bort profilbilden.');
    }
    return Profile.fromJson(data);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return ProfileRepository(client);
});
