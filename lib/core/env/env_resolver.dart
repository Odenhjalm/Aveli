import 'dart:io' show Platform;

import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvResolver {
  // URL to use in production builds
  static const String prodUrl = "https://your-production-backend.com";

  static String _readEnv(String key, {String defaultValue = ''}) {
    final value = dotenv.maybeGet(key);
    if (value != null && value.isNotEmpty) {
      return value;
    }
    return String.fromEnvironment(key, defaultValue: defaultValue);
  }

  static String get supabaseUrl => _readEnv('SUPABASE_URL');

  static String get supabaseAnonKey => _readEnv('SUPABASE_ANON_KEY');

  /// Resolve the correct API base URL depending on platform & build mode.
  static String get apiBaseUrl {
    // Optional dart-define for production overrides
    const buildMode = String.fromEnvironment("BUILD_MODE", defaultValue: "");

    if (buildMode == "prod") {
      return prodUrl;
    }

    // Android emulator cannot reach 127.0.0.1 on host.
    if (Platform.isAndroid) {
      return "http://10.0.2.2:8000";
    }

    // Desktop/Linux/macOS/iOS simulators can connect to local backend directly.
    if (Platform.isLinux ||
        Platform.isMacOS ||
        Platform.isIOS ||
        Platform.isWindows) {
      return "http://127.0.0.1:8000";
    }

    // Fallback
    return "http://127.0.0.1:8000";
  }
}
