// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:js' as js;

class BootBridge {
  static js.JsObject? _boot() {
    try {
      final dynamic boot = js.context['__AVELI_BOOT'];
      if (boot is js.JsObject) return boot;
    } catch (_) {}
    return null;
  }

  static String? _readString(js.JsObject? obj, String key) {
    if (obj == null) return null;
    try {
      final dynamic value = obj[key];
      if (value is String && value.isNotEmpty) return value;
    } catch (_) {}
    return null;
  }

  static String? get bootId => _readString(_boot(), 'boot_id');

  static String? get bootstrapVersion => _readString(_boot(), 'version');

  static String? get rendererMode {
    final boot = _boot();
    if (boot == null) return null;
    try {
      final dynamic renderer = boot['renderer'];
      if (renderer is js.JsObject) {
        return _readString(renderer, 'mode');
      }
    } catch (_) {}
    return null;
  }

  static String? get effectsPolicy {
    final boot = _boot();
    if (boot == null) return null;
    try {
      final dynamic renderer = boot['renderer'];
      if (renderer is js.JsObject) {
        return _readString(renderer, 'policy');
      }
    } catch (_) {}
    return null;
  }

  static void appReady(Map<String, Object?> payload) {
    final boot = _boot();
    if (boot == null) return;
    try {
      boot.callMethod('appReady', [js.JsObject.jsify(payload)]);
    } catch (_) {
      // Best effort.
    }
  }
}

