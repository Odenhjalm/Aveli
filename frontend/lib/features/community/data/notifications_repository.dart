import 'package:aveli/api/api_client.dart';

class NotificationsRepository {
  NotificationsRepository(ApiClient _);

  Future<List<Map<String, dynamic>>> myNotifications({
    bool unreadOnly = false,
  }) async {
    return const <Map<String, dynamic>>[];
  }

  Future<void> markRead(String id, {bool read = true}) async {
    return;
  }
}
