import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Lightweight logger for Image/NetworkImage errors.
///
/// Only logs in debug/profile to avoid noisy release builds.
class ImageErrorLogger {
  /// Global toggle; can be overridden at startup from AppConfig.
  static bool enabled = true;
  static void log({
    required String source,
    String? url,
    required Object error,
    StackTrace? stackTrace,
  }) {
    if (!enabled) return;
    if (!kDebugMode && !kProfileMode) return;
    final buf = StringBuffer('[IMG] $source');
    if (url != null && url.isNotEmpty) buf.write(' url=$url');

    // Try to extract status/uri for NetworkImage load errors.
    int? status;
    Uri? uri;
    try {
      if (error is NetworkImageLoadException) {
        status = error.statusCode;
        uri = error.uri;
      }
    } catch (_) {
      // Best effort; type may differ across platforms.
    }

    if (status != null) buf.write(' status=$status');
    if (uri != null) buf.write(' uri=${uri.toString()}');
    buf.write(' error=${error.runtimeType}: ${error.toString()}');
    debugPrint(buf.toString());
    if (stackTrace != null) {
      debugPrintStack(label: '[IMG] $source stack', stackTrace: stackTrace);
    }
  }
}
