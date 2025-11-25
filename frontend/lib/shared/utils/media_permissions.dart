import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result of requesting camera/microphone permissions.
class MediaPermissionResult {
  const MediaPermissionResult({
    required this.granted,
    required this.permanentlyDenied,
  });

  final bool granted;
  final bool permanentlyDenied;
}

/// Request camera and/or microphone permissions on platforms that require it.
///
/// On web and unsupported platforms the request is treated as granted.
Future<MediaPermissionResult> requestMediaPermissions({
  required bool camera,
  required bool microphone,
}) async {
  if (!_requiresRuntimePermission()) {
    return const MediaPermissionResult(granted: true, permanentlyDenied: false);
  }

  final permissions = <Permission>[];
  if (camera) {
    permissions.add(Permission.camera);
  }
  if (microphone) {
    permissions.add(Permission.microphone);
  }

  if (permissions.isEmpty) {
    return const MediaPermissionResult(granted: true, permanentlyDenied: false);
  }

  final statuses = await permissions.request();
  final granted = statuses.values.every((status) => status.isGranted);
  final permanentlyDenied = statuses.values.any(
    (status) => status.isPermanentlyDenied,
  );
  return MediaPermissionResult(
    granted: granted,
    permanentlyDenied: permanentlyDenied,
  );
}

/// Convenience helper to surface a SnackBar when permissions are missing.
void showMediaPermissionSnackbar(
  BuildContext context, {
  required MediaPermissionResult result,
}) {
  if (result.granted) return;
  final text = result.permanentlyDenied
      ? 'Ge appen åtkomst till kamera och mikrofon via systeminställningarna.'
      : 'Kamera- och mikrofonbehörighet krävs för live-sändningar.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

bool _requiresRuntimePermission() {
  if (kIsWeb) {
    return false;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    default:
      return false;
  }
}
