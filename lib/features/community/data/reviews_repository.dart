import 'package:wisdom/api/api_client.dart';

class ReviewsRepository {
  ReviewsRepository(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listByService(String serviceId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/community/services/$serviceId/reviews',
    );
    final items = (response['items'] as List? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    return items;
  }

  Future<void> add({
    required String serviceId,
    required int rating,
    String? comment,
  }) async {
    await _client.post(
      '/community/services/$serviceId/reviews',
      body: {
        'rating': rating,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      },
    );
  }
}
