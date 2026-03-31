import 'package:aveli/api/api_client.dart';

class ReviewsRepository {
  ReviewsRepository(ApiClient _);

  Future<T> _unsupportedRuntime<T>(String surface) {
    return Future<T>.error(
      UnsupportedError('$surface is inert in mounted runtime'),
    );
  }

  Future<List<Map<String, dynamic>>> listByService(String serviceId) async {
    return _unsupportedRuntime('Community service reviews');
  }

  Future<void> add({
    required String serviceId,
    required int rating,
    String? comment,
  }) async {
    return _unsupportedRuntime('Community service reviews');
  }
}
