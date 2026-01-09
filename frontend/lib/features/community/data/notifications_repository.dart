import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/errors/app_failure.dart';

class NotificationsRepository {
  NotificationsRepository(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> myNotifications({
    bool unreadOnly = false,
  }) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/community/notifications',
        queryParameters: {if (unreadOnly) 'unread_only': true},
      );
      return (response['items'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<void> markRead(String id, {bool read = true}) async {
    try {
      await _client.patch(
        '/community/notifications/$id',
        body: {'is_read': read},
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
