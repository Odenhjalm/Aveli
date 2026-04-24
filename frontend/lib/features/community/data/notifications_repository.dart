import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class DeviceRegistration {
  const DeviceRegistration({
    required this.id,
    required this.userId,
    required this.pushToken,
    required this.platform,
    required this.active,
  });

  final String id;
  final String userId;
  final String pushToken;
  final String platform;
  final bool active;

  factory DeviceRegistration.fromJson(Map<String, dynamic> json) {
    return DeviceRegistration(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      pushToken: json['push_token'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      active: json['active'] == true,
    );
  }
}

class NotificationsRepository {
  NotificationsRepository(this._client);

  final ApiClient _client;

  Future<List<NotificationItem>> myNotifications() async {
    final data = await _client.get<Map<String, dynamic>>(
      ApiPaths.notifications,
    );
    final items = data['items'] as List? ?? const [];
    return items
        .whereType<Map>()
        .map(
          (item) => NotificationItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  Future<DeviceRegistration> registerDevice({
    required String pushToken,
    required String platform,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      ApiPaths.notificationDevices,
      body: {'push_token': pushToken, 'platform': platform},
    );
    return DeviceRegistration.fromJson(data);
  }

  Future<void> deactivateDevice(String id) async {
    await _client.delete<void>(ApiPaths.notificationDevice(id));
  }
}
