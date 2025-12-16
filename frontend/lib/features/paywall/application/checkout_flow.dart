import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CheckoutItemType {
  membership,
  course,
  lesson,
  bundle,
  service,
}

@immutable
class CheckoutContext {
  CheckoutContext({
    required this.type,
    this.courseSlug,
    this.courseTitle,
    this.lessonId,
    this.lessonTitle,
    this.returnPath,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final CheckoutItemType type;
  final String? courseSlug;
  final String? courseTitle;
  final String? lessonId;
  final String? lessonTitle;
  final String? returnPath;
  final DateTime createdAt;
}

enum CheckoutRedirectStatus { idle, processing, success, canceled, error }

@immutable
class CheckoutRedirectState {
  const CheckoutRedirectState({
    required this.status,
    this.sessionId,
    this.error,
  });

  final CheckoutRedirectStatus status;
  final String? sessionId;
  final Object? error;

  static const idle = CheckoutRedirectState(status: CheckoutRedirectStatus.idle);

  CheckoutRedirectState copyWith({
    CheckoutRedirectStatus? status,
    String? sessionId,
    Object? error,
    bool clearError = false,
  }) {
    return CheckoutRedirectState(
      status: status ?? this.status,
      sessionId: sessionId ?? this.sessionId,
      error: clearError ? null : error ?? this.error,
    );
  }
}

/// Tracks the last started checkout so that success/cancel screens can
/// highlight the right course/lesson and navigate back.
final checkoutContextProvider = StateProvider<CheckoutContext?>((_) => null);

/// Tracks the most recent redirect/deep link handling outcome.
final checkoutRedirectStateProvider =
    StateProvider<CheckoutRedirectState>((_) => CheckoutRedirectState.idle);
