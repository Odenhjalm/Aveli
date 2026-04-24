import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/data/notifications_repository.dart';
import 'package:aveli/firebase_options.dart';

class PushDeviceRegistrar {
  PushDeviceRegistrar(this._notifications);

  final NotificationsRepository _notifications;
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _started = false;

  Future<void> registerCurrentDevice() async {
    if (_started) return;
    _started = true;

    final initialized = await _ensureFirebaseInitialized();
    if (!initialized) {
      _started = false;
      return;
    }

    final token = await _resolveToken();
    if (token != null && token.isNotEmpty) {
      await _registerToken(token);
    }

    try {
      _tokenRefreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh
          .listen((nextToken) {
            unawaited(_registerToken(nextToken));
          });
    } catch (_) {
      return;
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _started = false;
  }

  Future<String?> _resolveToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(provisional: true);
      return await messaging.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _ensureFirebaseInitialized() async {
    if (Firebase.apps.isNotEmpty) return true;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await _notifications.registerDevice(
        pushToken: token,
        platform: _platformName(),
      );
    } catch (_) {
      return;
    }
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }
}

final pushDeviceRegistrarProvider = Provider<PushDeviceRegistrar>((ref) {
  final registrar = PushDeviceRegistrar(
    ref.watch(notificationsRepositoryProvider),
  );
  ref.onDispose(() {
    unawaited(registrar.dispose());
  });
  return registrar;
});
