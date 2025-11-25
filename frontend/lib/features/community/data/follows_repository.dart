import 'package:wisdom/api/api_client.dart';
import 'package:wisdom/core/errors/app_failure.dart';

class FollowsRepository {
  FollowsRepository(this._client);

  final ApiClient _client;

  Future<void> follow(String userId) async {
    try {
      await _client.post('/community/follows/$userId');
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<void> unfollow(String userId) async {
    try {
      await _client.delete('/community/follows/$userId');
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
