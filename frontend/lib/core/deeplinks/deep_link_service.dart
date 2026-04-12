import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/routing/app_router.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/paywall/application/checkout_flow.dart';

final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final service = DeepLinkService(ref);
  ref.onDispose(service.dispose);
  return service;
});

class DeepLinkService {
  DeepLinkService(this._ref);

  final Ref _ref;
  bool _initialized = false;
  static Uri? _pendingInitialUri;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb) return;
    final initial = _pendingInitialUri;
    _pendingInitialUri = null;
    if (initial != null) {
      await handleUri(initial);
    }
  }

  /// Exposed so WebViews or manual triggers can forward a redirect URI directly
  /// instead of waiting for the OS to broadcast it.
  Future<bool> handleUri(Uri uri) async {
    if (_isAuthCallbackUri(uri)) {
      await _handleAuthCallback(uri);
      return true;
    }
    if (!_isCheckoutUri(uri)) return false;
    final isSuccess = _isSuccessPath(uri);
    final isCancel = _isCancelPath(uri);

    if (isSuccess) {
      await _handleCheckoutSuccess(uri);
      return true;
    } else if (isCancel) {
      _handleCheckoutCancel();
      return true;
    }
    return false;
  }

  bool _isCheckoutUri(Uri uri) {
    final schemeOk = uri.scheme == 'aveliapp' || uri.scheme == 'https';
    final hostOk =
        uri.host == 'checkout' || uri.host.contains('aveli.app') == true;
    final pathOk = _isSuccessPath(uri) || _isCancelPath(uri);
    return schemeOk && hostOk && pathOk;
  }

  bool _isAuthCallbackUri(Uri uri) {
    final isAppScheme =
        uri.scheme == 'aveliapp' &&
        (uri.host == 'auth-callback' || uri.path.contains('auth-callback'));
    final isAuthCallback =
        uri.path.toLowerCase().contains('auth/callback') ||
        uri.path.toLowerCase().contains('auth-callback');
    final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
    return isAppScheme || (isHttp && isAuthCallback);
  }

  bool _isSuccessPath(Uri uri) {
    final path = uri.path.toLowerCase();
    return path.contains('success') ||
        path.contains('checkout/return') ||
        (uri.host == 'checkout' && path.contains('return'));
  }

  bool _isCancelPath(Uri uri) {
    final path = uri.path.toLowerCase();
    return path.contains('cancel');
  }

  Future<void> _handleCheckoutSuccess(Uri uri) async {
    final sessionId = uri.queryParameters['session_id'];
    if (sessionId == null || sessionId.isEmpty) {
      _handleMissingSession();
      return;
    }
    final currentRedirect = _ref.read(checkoutRedirectStateProvider);
    _ref
        .read(checkoutRedirectStateProvider.notifier)
        .state = CheckoutRedirectState(
      status: CheckoutRedirectStatus.processing,
      sessionId: sessionId,
      orderId: currentRedirect.orderId,
    );
    await _ref.read(authControllerProvider.notifier).loadSession();
    _ref
        .read(checkoutRedirectStateProvider.notifier)
        .state = CheckoutRedirectState(
      status: CheckoutRedirectStatus.success,
      sessionId: sessionId,
      orderId: currentRedirect.orderId,
    );
    _goWithQuery(
      RoutePath.checkoutSuccess,
      sessionId: sessionId,
      orderId: currentRedirect.orderId,
    );
  }

  void _handleCheckoutCancel() {
    final currentRedirect = _ref.read(checkoutRedirectStateProvider);
    _ref
        .read(checkoutRedirectStateProvider.notifier)
        .state = CheckoutRedirectState(
      status: CheckoutRedirectStatus.canceled,
      sessionId: currentRedirect.sessionId,
      orderId: currentRedirect.orderId,
    );
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
    final router = _ref.read(appRouterProvider);
    router.go(RoutePath.checkoutCancel);
  }

  void _handleMissingSession() {
    _ref
        .read(checkoutRedirectStateProvider.notifier)
        .state = const CheckoutRedirectState(
      status: CheckoutRedirectStatus.error,
      error: 'Saknar session_id i checkout-redirect.',
    );
    _goWithQuery(RoutePath.checkoutSuccess, errored: true);
  }

  void _goWithQuery(
    String path, {
    String? sessionId,
    String? orderId,
    bool errored = false,
  }) {
    final params = <String, String>{};
    if (sessionId != null && sessionId.isNotEmpty) {
      params['session_id'] = sessionId;
    }
    if (orderId != null && orderId.isNotEmpty) {
      params['order_id'] = orderId;
    }
    if (errored) params['errored'] = '1';
    final uri = params.isEmpty
        ? path
        : Uri(path: path, queryParameters: params).toString();
    final router = _ref.read(appRouterProvider);
    router.go(uri);
  }

  Future<void> _handleAuthCallback(Uri uri) async {
    final router = _ref.read(appRouterProvider);
    final redirect = _sanitizeRedirect(uri.queryParameters['redirect']);
    final target = Uri(
      path: RoutePath.login,
      queryParameters: {
        if (redirect != null && redirect.isNotEmpty) 'redirect': redirect,
      },
    ).toString();
    router.go(target);
  }

  String? _sanitizeRedirect(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return raw.startsWith('/') ? raw : null;
  }

  void dispose() {
    _initialized = false;
  }

  /// Allows tests or embedding contexts to inject a deferred initial URI
  /// without relying on platform deep link plugins.
  static void injectInitialUri(Uri uri) {
    _pendingInitialUri = uri;
  }
}
