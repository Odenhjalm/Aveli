import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:media_kit_video/media_kit_video.dart';

bool mediaKitVideoEnabled() {
  if (kIsWeb) {
    return false;
  }
  final env = Platform.environment;

  if (_isTruthy(env['WISDOM_DISABLE_MEDIA_KIT'])) {
    return false;
  }

  final override =
      env['WISDOM_ENABLE_MEDIA_KIT'] ??
      env['WISDOM_FORCE_MEDIA_KIT'] ??
      env['WISDOM_MEDIA_KIT'] ??
      env['WISDOM_USE_MEDIA_KIT'];

  if (_isTruthy(override)) {
    return true;
  }
  if (_isFalsy(override)) {
    return false;
  }

  if (Platform.isAndroid) {
    return false;
  }

  // Enabled by default on all other non-web targets unless explicitly disabled.
  return true;
}

VideoControllerConfiguration? mediaKitVideoConfiguration() {
  if (kIsWeb) return null;
  final env = Platform.environment;

  String? vo = _stringOrNull(env['WISDOM_MEDIA_KIT_VO']);
  String? hwdec = _stringOrNull(env['WISDOM_MEDIA_KIT_HWDEC']);

  final hwAccelOverrideRaw =
      env['WISDOM_MEDIA_KIT_HWACCEL'] ??
      env['WISDOM_MEDIA_KIT_HARDWARE_ACCELERATION'];
  bool? hardwareAcceleration;
  if (_isTruthy(hwAccelOverrideRaw)) {
    hardwareAcceleration = true;
  } else if (_isFalsy(hwAccelOverrideRaw)) {
    hardwareAcceleration = false;
  }

  if (Platform.isLinux) {
    hardwareAcceleration ??= false;
    hwdec ??= 'no';
  }

  if (hardwareAcceleration == null && hwdec == null && vo == null) {
    return null;
  }

  return VideoControllerConfiguration(
    vo: vo,
    hwdec: hwdec,
    enableHardwareAcceleration: hardwareAcceleration ?? true,
  );
}

String? _stringOrNull(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _isTruthy(String? value) {
  if (value == null) return false;
  switch (value.trim().toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
    case 'y':
    case 'on':
      return true;
    default:
      return false;
  }
}

bool _isFalsy(String? value) {
  if (value == null) return false;
  switch (value.trim().toLowerCase()) {
    case '0':
    case 'false':
    case 'no':
    case 'n':
    case 'off':
      return true;
    default:
      return false;
  }
}
