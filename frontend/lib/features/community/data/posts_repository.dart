import 'dart:async';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/data/models/community_post.dart';

class PostsRepository {
  PostsRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<List<CommunityPost>> feed({int limit = 50}) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/community/posts',
        queryParameters: {'limit': limit},
      );
      final items = (response['items'] as List? ?? [])
          .map(
            (item) =>
                CommunityPost.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false);
      return items;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<CommunityPost> create({
    required String content,
    List<String>? mediaPaths,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/community/posts',
        body: {
          'content': content,
          if (mediaPaths != null && mediaPaths.isNotEmpty)
            'media_paths': mediaPaths,
        },
      );
      return CommunityPost.fromJson(response);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
