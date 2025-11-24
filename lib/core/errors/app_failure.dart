import 'dart:async';

import 'package:dio/dio.dart';

/// High-level error classification used across repositories and providers.
enum AppFailureKind {
  network,
  unauthorized,
  notFound,
  validation,
  timeout,
  server,
  configuration,
  unexpected,
}

sealed class AppFailure implements Exception {
  const AppFailure({
    required this.kind,
    required this.message,
    this.code,
    this.original,
    this.stackTrace,
  });

  final AppFailureKind kind;
  final String message;
  final String? code;
  final Object? original;
  final StackTrace? stackTrace;

  factory AppFailure.from(Object error, [StackTrace? stackTrace]) {
    if (error is AppFailure) return error;

    if (error is TimeoutException) {
      return TimeoutFailure(
        message:
            'Tidsgränsen överskreds. Kontrollera din uppkoppling och försök igen.',
        original: error,
        stackTrace: stackTrace,
      );
    }

    if (_looksLikeConfigError(error)) {
      return ConfigurationFailure(
        message: 'API är inte korrekt konfigurerat.',
        original: error,
        stackTrace: stackTrace,
      );
    }

    if (error is DioException) {
      return _fromDio(error, stackTrace);
    }

    if (_looksLikeNetworkIssue(error)) {
      return NetworkFailure(
        message: 'Kunde inte nå servern. Försök igen.',
        original: error,
        stackTrace: stackTrace,
      );
    }

    return UnexpectedFailure(
      message: error.toString(),
      original: error,
      stackTrace: stackTrace,
    );
  }

  static AppFailure _fromDio(DioException error, StackTrace? stackTrace) {
    final status = error.response?.statusCode ?? 0;
    final payload = error.response?.data;
    final detail = _extractDetail(payload);
    if (status == 0) {
      return NetworkFailure(
        message: 'Kunde inte nå servern. Försök igen.',
        original: error,
        stackTrace: stackTrace,
      );
    }
    if (status == 401 || status == 403) {
      final message = detail != null
          ? _localizeDetail(detail)
          : 'Behörighet saknas. Logga in igen.';
      return UnauthorizedFailure(
        message: message,
        original: error,
        stackTrace: stackTrace,
      );
    }
    if (status == 404) {
      return NotFoundFailure(
        message: detail != null
            ? _localizeDetail(detail)
            : 'Resursen kunde inte hittas.',
        original: error,
        stackTrace: stackTrace,
      );
    }
    if (status == 402) {
      return ValidationFailure(
        message: detail != null
            ? _localizeDetail(detail)
            : 'Betalningen kunde inte genomföras. Kontrollera dina betalningsuppgifter och försök igen.',
        original: error,
        stackTrace: stackTrace,
      );
    }
    if (status >= 400 && status < 500) {
      return ValidationFailure(
        message: detail != null
            ? _localizeDetail(detail)
            : 'Förfrågan kunde inte behandlas. Kontrollera uppgifterna och försök igen.',
        original: error,
        stackTrace: stackTrace,
      );
    }
    return ServerFailure(
      message:
          'Serverfel ($status). Försök igen senare eller kontakta supporten om problemet kvarstår.',
      original: error,
      stackTrace: stackTrace,
    );
  }

  static bool _looksLikeConfigError(Object error) {
    final text = error.toString().toLowerCase();
    final mentionsApi =
        text.contains('api_base_url') ||
        text.contains('api base url') ||
        text.contains('api');
    final mentionsConfig =
        text.contains('konfig') ||
        text.contains('config') ||
        text.contains('init');
    final mentionsMissing = text.contains('saknas') || text.contains('missing');
    return mentionsApi && mentionsConfig && mentionsMissing;
  }

  static bool _looksLikeNetworkIssue(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable');
  }

  @override
  String toString() =>
      'AppFailure(kind: $kind, message: $message, code: $code)';
}

String? _extractDetail(dynamic data) {
  if (data == null) return null;
  if (data is String && data.trim().isNotEmpty) {
    return data.trim();
  }
  if (data is Map) {
    for (final key in ['detail', 'message', 'error', 'description']) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
  }
  return null;
}

String _localizeDetail(String detail) {
  switch (detail.toLowerCase()) {
    case 'invalid credentials':
      return 'Fel e-postadress eller lösenord.';
    case 'email already registered':
      return 'E-postadressen är redan registrerad.';
    case 'user not found':
      return 'Kontot kunde inte hittas.';
    case 'unauthorized':
      return 'Behörighet saknas. Logga in igen.';
    case 'forbidden':
    case 'forbidden_action':
    case 'not_allowed':
      return 'Du har inte behörighet att utföra den här åtgärden.';
    case 'payment required':
    case 'payment_failed':
    case 'payment_failed_error':
      return 'Betalningen misslyckades. Kontrollera dina betalningsuppgifter.';
    case 'card_declined':
      return 'Kortet nekades av banken. Prova ett annat kort eller kontakta banken.';
    case 'insufficient_funds':
      return 'Kortet har otillräckligt saldo för att genomföra köpet.';
    default:
      return detail;
  }
}

class NetworkFailure extends AppFailure {
  NetworkFailure({
    required super.message,
    super.code,
    super.original,
    super.stackTrace,
  }) : super(kind: AppFailureKind.network);
}

class UnauthorizedFailure extends AppFailure {
  UnauthorizedFailure({
    required super.message,
    super.code,
    super.original,
    super.stackTrace,
  }) : super(kind: AppFailureKind.unauthorized);
}

class NotFoundFailure extends AppFailure {
  NotFoundFailure({
    required super.message,
    super.code,
    super.original,
    super.stackTrace,
  }) : super(kind: AppFailureKind.notFound);
}

class ValidationFailure extends AppFailure {
  ValidationFailure({
    required super.message,
    super.code,
    super.original,
    super.stackTrace,
  }) : super(kind: AppFailureKind.validation);
}

class TimeoutFailure extends AppFailure {
  TimeoutFailure({
    required super.message,
    super.code,
    super.original,
    super.stackTrace,
  }) : super(kind: AppFailureKind.timeout);
}

class ServerFailure extends AppFailure {
  ServerFailure({
    required super.message,
    super.code,
    super.original,
    super.stackTrace,
  }) : super(kind: AppFailureKind.server);
}

class ConfigurationFailure extends AppFailure {
  ConfigurationFailure({
    required super.message,
    super.code,
    super.original,
    super.stackTrace,
  }) : super(kind: AppFailureKind.configuration);
}

class UnexpectedFailure extends AppFailure {
  UnexpectedFailure({
    required super.message,
    super.code,
    super.original,
    super.stackTrace,
  }) : super(kind: AppFailureKind.unexpected);
}
