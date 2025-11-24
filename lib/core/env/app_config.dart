import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.stripePublishableKey,
    required this.stripeMerchantDisplayName,
    required this.subscriptionsEnabled,
    this.imageLoggingEnabled = false,
  });

  final String apiBaseUrl;
  final String stripePublishableKey;
  final String stripeMerchantDisplayName;
  final bool subscriptionsEnabled;
  final bool imageLoggingEnabled;
}

final appConfigProvider = Provider<AppConfig>((ref) {
  throw UnimplementedError('AppConfig has not been initialized');
});
