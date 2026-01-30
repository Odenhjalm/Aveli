import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class BootLog {
  BootLog._();

  static String _bootId = 'unknown';
  static String get bootId => _bootId;

  static void init({required String bootId}) {
    _bootId = bootId;
    event('boot_log_init', {});
  }

  static void transition({
    required String from,
    required String to,
    Map<String, Object?> data = const {},
  }) {
    event('transition', {'from': from, 'to': to, 'data': data});
  }

  static void event(String type, Map<String, Object?> data, {int level = 800}) {
    final payload = <String, Object?>{
      'boot_id': _bootId,
      'type': type,
      'data': data,
      'ts': DateTime.now().toIso8601String(),
    };
    final text = '[BOOT] ${jsonEncode(payload)}';
    developer.log(text, name: 'boot', level: level);
    // Developer-friendly mirror. In release builds (especially on Web),
    // `developer.log` is not reliably visible in the browser console, so we
    // mirror to stdout as well to keep boot events observable.
    if (kDebugMode) {
      debugPrint(text);
    } else {
      // ignore: avoid_print
      print(text);
    }
  }

  static void criticalAsset({
    required String name,
    required String status,
    required String path,
    Object? error,
  }) {
    event('critical_asset', {
      'name': name,
      'status': status,
      'path': path,
      if (error != null) 'error': error.toString(),
    }, level: status == 'loaded' ? 800 : 1000);
  }
}
