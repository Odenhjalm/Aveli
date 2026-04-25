import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';

class NotificationHeaderItem {
  const NotificationHeaderItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.ctaUrl,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? ctaLabel;
  final String? ctaUrl;

  factory NotificationHeaderItem.fromJson(Map<String, dynamic> json) {
    return NotificationHeaderItem(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      subtitle: _optionalString(json, 'subtitle'),
      ctaLabel: _optionalString(json, 'cta_label'),
      ctaUrl: _optionalString(json, 'cta_url'),
    );
  }
}

class NotificationsReadModel {
  const NotificationsReadModel({
    required this.showNotificationsBar,
    required this.notifications,
  });

  final bool showNotificationsBar;
  final List<NotificationHeaderItem> notifications;

  factory NotificationsReadModel.fromJson(Map<String, dynamic> json) {
    final notifications = json['notifications'];
    if (notifications is! List) {
      throw StateError('notifications must be a list');
    }
    return NotificationsReadModel(
      showNotificationsBar: _requiredBool(json, 'show_notifications_bar'),
      notifications: notifications
          .map((item) {
            if (item is! Map) {
              throw StateError('notification item must be an object');
            }
            return NotificationHeaderItem.fromJson(
              Map<String, dynamic>.from(item),
            );
          })
          .toList(growable: false),
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

  Future<NotificationsReadModel> myNotifications() async {
    final data = await _client.get<Map<String, dynamic>>(
      ApiPaths.notifications,
    );
    return NotificationsReadModel.fromJson(data);
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

  Future<NotificationHeaderItem> markRead(String id) async {
    final data = await _client.patch<Map<String, dynamic>>(
      ApiPaths.notificationRead(id),
    );
    return NotificationHeaderItem.fromJson(data ?? const <String, dynamic>{});
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw StateError('$key must be a non-empty string');
  }
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw StateError('$key must be a boolean');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw StateError('$key must be a string or null');
  }
  return value;
}
