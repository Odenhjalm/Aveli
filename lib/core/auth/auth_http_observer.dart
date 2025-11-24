import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Events emitted by the HTTP layer regarding authentication state.
enum AuthHttpEvent {
  /// Access token is no longer valid and refresh failed.
  sessionExpired,

  /// Request was forbidden for the current user (403).
  forbidden,
}

class AuthHttpObserver {
  final StreamController<AuthHttpEvent> _controller =
      StreamController<AuthHttpEvent>.broadcast();

  Stream<AuthHttpEvent> get events => _controller.stream;

  void emit(AuthHttpEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  @mustCallSuper
  void dispose() {
    _controller.close();
  }
}

final authHttpObserverProvider = Provider<AuthHttpObserver>((ref) {
  final observer = AuthHttpObserver();
  ref.onDispose(observer.dispose);
  return observer;
});

final authHttpEventsProvider = StreamProvider<AuthHttpEvent>((ref) {
  final observer = ref.watch(authHttpObserverProvider);
  return observer.events;
});
