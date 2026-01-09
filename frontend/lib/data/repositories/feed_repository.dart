import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/data/models/activity.dart';

class FeedRepository {
  const FeedRepository(this._client);

  final ApiClient _client;

  Future<List<Activity>> fetchFeed({int limit = 20}) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/feed',
      queryParameters: {'limit': limit},
    );
    final items = response['items'] as List? ?? const [];
    return items
        .map(
          (item) => Activity.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }
}

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return FeedRepository(client);
});
