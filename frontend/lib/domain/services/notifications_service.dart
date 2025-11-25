import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class NotificationsService {
  static final NotificationsService instance = NotificationsService._();
  NotificationsService._();

  FirebaseMessaging? get _fm {
    try {
      return FirebaseMessaging.instance;
    } catch (_) {
      return null;
    }
  }

  /// Requests permissions (iOS), returns FCM token if available.
  Future<String?> initAndGetToken() async {
    final fm = _fm;
    if (fm == null) return null;
    if (!kIsWeb) {
      await fm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
    }
    // Foreground message handler (no-op by default; let app set listener)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // You can surface in-app banners/snackbars from caller
    });
    return fm.getToken();
  }

  /// Legacy helper kept for API compatibility. REST/websocket-based
  /// notifications are not implemented yet, so this returns `null`.
  Future<VoidCallback?> watchMyNotifications({
    required void Function(Map<String, dynamic> row) onInsert,
  }) async => null;
}
