import 'dart:async';
import 'package:firebase_remote_config/firebase_remote_config.dart';

class RemoteConfigService {
  static final RemoteConfigService instance = RemoteConfigService._();
  RemoteConfigService._();

  FirebaseRemoteConfig? get _rc {
    try {
      return FirebaseRemoteConfig.instance;
    } catch (_) {
      return null;
    }
  }

  Future<void> init({
    Duration fetchTimeout = const Duration(seconds: 10),
    Duration minimumFetchInterval = const Duration(hours: 1),
    Map<String, RemoteConfigValue> defaults = const {},
  }) async {
    final rc = _rc;
    if (rc == null) return;
    await rc.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: fetchTimeout,
        minimumFetchInterval: minimumFetchInterval,
      ),
    );
    if (defaults.isNotEmpty) {
      await rc.setDefaults(defaults);
    }
    await rc.fetchAndActivate();
  }

  String getString(String key, {String fallback = ''}) {
    final rc = _rc;
    if (rc == null) return fallback;
    return rc.getString(key).isNotEmpty ? rc.getString(key) : fallback;
  }

  bool getBool(String key, {bool fallback = false}) {
    final rc = _rc;
    if (rc == null) return fallback;
    return rc.getBool(key);
  }

  int getInt(String key, {int fallback = 0}) {
    final rc = _rc;
    if (rc == null) return fallback;
    return rc.getInt(key);
  }
}
