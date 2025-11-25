import 'package:aveli/core/env/env_resolver.dart';

/// Determines which backend base URL should be used for the MVP demo.
class MvpAppConfig {
  const MvpAppConfig({required this.baseUrl});

  final String baseUrl;

  factory MvpAppConfig.auto() {
    return MvpAppConfig(baseUrl: resolveBaseUrl());
  }

  static String resolveBaseUrl() {
    final env = const String.fromEnvironment('MVP_BASE_URL');
    if (env.isNotEmpty) {
      return env;
    }
    return EnvResolver.apiBaseUrl;
  }
}
