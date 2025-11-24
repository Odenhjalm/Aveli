import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import 'package:wisdom/api/api_client.dart';
import 'package:wisdom/api/auth_repository.dart';
import 'package:wisdom/data/models/profile.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final ApiClient _client;

  Future<Profile?> getMe() async {
    final data = await _client.get<Map<String, dynamic>>('/auth/me');
    if (data.isEmpty) return null;
    return Profile.fromJson(data);
  }

  Future<Profile> updateMe({
    String? displayName,
    String? bio,
    String? photoUrl,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) {
      body['display_name'] = displayName;
    }
    if (bio != null) {
      body['bio'] = bio;
    }
    if (photoUrl != null) {
      body['photo_url'] = photoUrl;
    }

    final data = await _client.patch<Map<String, dynamic>>(
      '/auth/me',
      body: body.isEmpty ? null : body,
    );
    if (data == null || data.isEmpty) {
      throw StateError('Failed to update profile');
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

    final uploadResponse = await _client.postForm<Map<String, dynamic>>(
      '/api/upload/profile',
      formData,
    );
    final url = uploadResponse?['url'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('Failed to upload avatar');
    }
    return updateMe(photoUrl: url);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return ProfileRepository(client);
});
