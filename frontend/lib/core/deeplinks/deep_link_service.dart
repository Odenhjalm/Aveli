import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:uni_links/uni_links.dart';
import 'package:wisdom/core/auth/auth_controller.dart';
import 'package:wisdom/core/routing/app_router.dart';
import 'package:wisdom/core/routing/route_paths.dart';
import 'package:wisdom/features/paywall/application/checkout_flow.dart';

final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final service = DeepLinkService(ref);
  ref.onDispose(service.dispose);
  return service;
});

class DeepLinkService {
  DeepLinkService(this._ref);

  final Ref _ref;
  StreamSubscription<Uri?>? _sub;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    // Web cannot listen for deep link streams; redirects come via full page load.
    if (kIsWeb) {
      return;
    }
    await _processInitialUri();
    _sub = uriLinkStream.listen(
      (uri) {
        if (uri != null) {
          unawaited(handleUri(uri));
        }
      },
      onError: (err) {
        debugPrint('Deep link stream error: $err');
      },
    );
  }

  Future<void> _processInitialUri() async {
    try {
      final initial = await getInitialUri();
      if (initial != null) {
        await handleUri(initial);
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to process initial URI: $error');
      debugPrint(stackTrace.toString());
    }
  }

  /// Exposed so WebViews or manual triggers can forward a redirect URI directly
  /// instead of waiting for the OS to broadcast it.
  Future<void> handleUri(Uri uri) async {
    if (_isAuthCallbackUri(uri)) {
      await _handleAuthCallback(uri);
      return;
    }
    if (!_isCheckoutUri(uri)) return;
    final isSuccess = _isSuccessPath(uri);
    final isCancel = _isCancelPath(uri);

    if (isSuccess) {
      await _handleCheckoutSuccess(uri);
    } else if (isCancel) {
      _handleCheckoutCancel();
    }
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
    final isAuthCallback = uri.path.toLowerCase().contains('auth/callback') ||
        uri.path.toLowerCase().contains('auth-callback');
    final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
    return isAppScheme || (isHttp && isAuthCallback);
  }

  bool _isSuccessPath(Uri uri) {
    final path = uri.path.toLowerCase();
    return path.contains('success');
  }

  bool _isCancelPath(Uri uri) {
    final path = uri.path.toLowerCase();
    return path.contains('cancel');
  }

  Future<void> _handleCheckoutSuccess(Uri uri) async {
    final sessionId = uri.queryParameters['session_id'];
    final subscriptionStatus = uri.queryParameters['subscription_status'];
    if (sessionId == null || sessionId.isEmpty) {
      _handleMissingSession();
      return;
    }
    _ref.read(checkoutRedirectStateProvider.notifier).state =
        CheckoutRedirectState(
      status: CheckoutRedirectStatus.processing,
      sessionId: sessionId,
    );
    _goWithQuery(
      RoutePath.checkoutSuccess,
      sessionId: sessionId,
      extraParams: {
        if (subscriptionStatus != null && subscriptionStatus.isNotEmpty)
          'subscription_status': subscriptionStatus,
      },
    );
  }

  void _handleCheckoutCancel() {
    _ref.read(checkoutRedirectStateProvider.notifier).state =
        const CheckoutRedirectState(status: CheckoutRedirectStatus.canceled);
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
    bool errored = false,
    Map<String, String>? extraParams,
  }) {
    final params = <String, String>{
      if (extraParams != null) ...extraParams,
    };
    if (sessionId != null && sessionId.isNotEmpty) {
      params['session_id'] = sessionId;
    }
    if (errored) params['errored'] = '1';
    final uri = params.isEmpty
        ? path
        : Uri(path: path, queryParameters: params).toString();
    final router = _ref.read(appRouterProvider);
    router.go(uri);
  }

  Future<void> _handleAuthCallback(Uri uri) async {
    try {
      debugPrint('Deep link auth callback uri: $uri');
      final res = await supa.Supabase.instance.client.auth.getSessionFromUrl(
        uri,
        storeSession: true,
      );
      debugPrint('Deep link getSessionFromUrl session=${res.session}');
    } catch (error, stackTrace) {
      final errorParam = uri.queryParameters['error'];
      final errorDescription = uri.queryParameters['error_description'];
      debugPrint(
        'Auth callback session recovery failed: $error '
        '(error=$errorParam, description=$errorDescription, uri=$uri)',
      );
      debugPrint(stackTrace.toString());
    }
    if (supa.Supabase.instance.client.auth.currentSession != null) {
      try {
        await HapticFeedback.mediumImpact();
      } catch (_) {}
    }
    final router = _ref.read(appRouterProvider);
    final redirect = _sanitizeRedirect(uri.queryParameters['redirect']);
    router.go(redirect ?? RoutePath.home);
  }

  String? _sanitizeRedirect(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return raw.startsWith('/') ? raw : null;
  }

  void dispose() {
    _sub?.cancel();
    _initialized = false;
  }
}
