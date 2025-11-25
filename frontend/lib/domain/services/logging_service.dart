import 'dart:developer' as developer;

class LoggingService {
  LoggingService._();

  static final LoggingService instance = LoggingService._();

  void logInfo(String message, {Map<String, Object?> extras = const {}}) {
    final formatted = _format(message, extras);
    developer.log(
      formatted,
      name: 'LiveKit',
      level: 800,
      error: null,
      stackTrace: null,
      zone: null,
      sequenceNumber: null,
      time: DateTime.now(),
    );
  }

  void logError(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> extras = const {},
  }) {
    final formatted = _format(message, extras);
    developer.log(
      formatted,
      name: 'LiveKit',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
      zone: null,
      sequenceNumber: null,
      time: DateTime.now(),
    );
  }

  String _format(String message, Map<String, Object?> extras) {
    if (extras.isEmpty) return message;
    return '$message | ${extras.toString()}';
  }
}
