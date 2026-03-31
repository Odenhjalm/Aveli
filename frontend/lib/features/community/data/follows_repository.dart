import 'package:aveli/api/api_client.dart';
class FollowsRepository {
  FollowsRepository(ApiClient _);

  Future<T> _unsupportedRuntime<T>(String surface) {
    return Future<T>.error(
      UnsupportedError('$surface is inert in mounted runtime'),
    );
  }

  Future<void> follow(String userId) async {
    return _unsupportedRuntime('Community follows');
  }

  Future<void> unfollow(String userId) async {
    return _unsupportedRuntime('Community follows');
  }
}
