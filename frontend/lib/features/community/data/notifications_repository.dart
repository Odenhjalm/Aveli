import 'package:aveli/api/api_client.dart';
class NotificationsRepository {
  NotificationsRepository(ApiClient _);

  Future<T> _unsupportedRuntime<T>(String surface) {
    return Future<T>.error(
      UnsupportedError('$surface is inert in mounted runtime'),
    );
  }

  Future<List<Map<String, dynamic>>> myNotifications({
    bool unreadOnly = false,
  }) async {
    return _unsupportedRuntime('Community notifications');
  }

  Future<void> markRead(String id, {bool read = true}) async {
    return _unsupportedRuntime('Community notifications');
  }
}
