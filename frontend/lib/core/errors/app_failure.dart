import 'dart:async';

import 'package:dio/dio.dart';

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
            'Tidsgransen overskreds. Kontrollera din uppkoppling och forsok igen.',
        original: error,
        stackTrace: stackTrace,
      );
    }

    if (_looksLikeConfigError(error)) {
      return ConfigurationFailure(
        message: 'API ar inte korrekt konfigurerat.',
        original: error,
        stackTrace: stackTrace,
      );
    }

    if (error is DioException) {
      return _fromDio(error, stackTrace);
    }

    if (_looksLikeNetworkIssue(error)) {
      return NetworkFailure(
        message: 'Kunde inte na servern. Forsok igen.',
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
    final canonical = _extractCanonicalError(payload);
    final fallbackDetail = _extractFallbackDetail(payload);
    if (status == 0) {
      return NetworkFailure(
        message: 'Kunde inte na servern. Forsok igen.',
        original: error,
        stackTrace: stackTrace,
      );
    }

    final message =
        canonical?.message ??
        (fallbackDetail != null ? _localizeDetail(fallbackDetail) : null);
    final code = canonical?.errorCode;

    if (status == 401 || status == 403) {
      return UnauthorizedFailure(
        message: message ?? 'Behorighet saknas. Logga in igen.',
        code: code,
        original: error,
        stackTrace: stackTrace,
      );
    }
    if (status == 404) {
      return NotFoundFailure(
        message: message ?? 'Resursen kunde inte hittas.',
        code: code,
        original: error,
        stackTrace: stackTrace,
      );
    }
    if (status >= 400 && status < 500) {
      return ValidationFailure(
        message:
            message ??
            'Forfragan kunde inte behandlas. Kontrollera uppgifterna och forsok igen.',
        code: code,
        original: error,
        stackTrace: stackTrace,
      );
    }
    return ServerFailure(
      message:
          message ??
          'Serverfel ($status). Forsok igen senare eller kontakta supporten om problemet kvarstar.',
      code: code,
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

class _CanonicalErrorEnvelope {
  const _CanonicalErrorEnvelope({
    required this.errorCode,
    required this.message,
  });

  final String errorCode;
  final String message;
}

_CanonicalErrorEnvelope? _extractCanonicalError(dynamic data) {
  if (data is! Map) return null;
  final status = data['status'];
  final errorCode = data['error_code'];
  final message = data['message'];
  if (status == 'error' &&
      errorCode is String &&
      errorCode.trim().isNotEmpty &&
      message is String &&
      message.trim().isNotEmpty) {
    return _CanonicalErrorEnvelope(
      errorCode: errorCode.trim(),
      message: message.trim(),
    );
  }
  return null;
}

String? _extractFallbackDetail(dynamic data) {
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
    case 'invalid_credentials':
      return 'Fel e-postadress eller losenord.';
    case 'email already registered':
    case 'email_already_registered':
      return 'E-postadressen ar redan registrerad.';
    case 'user not found':
    case 'user_not_found':
      return 'Kontot kunde inte hittas.';
    case 'invalid_or_expired_token':
      return 'Lanken ar ogiltig eller har gatt ut.';
    case 'invalid_current_password':
      return 'Nuvarande losenord ar fel.';
    case 'new_password_must_differ':
      return 'Det nya losenordet maste skilja sig fran det nuvarande.';
    case 'rate_limited':
      return 'For manga forsok. Vanta en stund och forsok igen.';
    case 'unauthorized':
    case 'unauthenticated':
      return 'Behorighet saknas. Logga in igen.';
    case 'forbidden':
    case 'forbidden_action':
    case 'not_allowed':
    case 'admin_required':
      return 'Du har inte behorighet att utfora den har atgarden.';
    case 'payment required':
    case 'payment_failed':
    case 'payment_failed_error':
      return 'Betalningen misslyckades. Kontrollera dina betalningsuppgifter.';
    case 'card_declined':
      return 'Kortet nekades av banken. Prova ett annat kort eller kontakta banken.';
    case 'insufficient_funds':
      return 'Kortet har otillrackligt saldo for att genomfora kopet.';
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
