import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/deeplinks/deep_link_service.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/paywall/application/checkout_flow.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';

class CheckoutWebViewPage extends ConsumerStatefulWidget {
  const CheckoutWebViewPage({super.key, required this.url});

  final String url;

  @override
  ConsumerState<CheckoutWebViewPage> createState() =>
      _CheckoutWebViewPageState();
}

class _CheckoutWebViewPageState extends ConsumerState<CheckoutWebViewPage> {
  late final WebViewController _controller;
  bool _refreshed = false;
  bool _embeddedUnavailable = false;
  bool _navigatedAway = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb || (!kIsWeb && (Platform.isLinux || Platform.isWindows))) {
      _embeddedUnavailable = true;
      return;
    }
    _ensureWebViewPlatform();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url;
            if (_isSuccessUrl(url)) {
              _handleCheckoutRedirect(url);
              return NavigationDecision.prevent;
            }
            if (_isCancelUrl(url)) {
              _handleCheckoutRedirect(url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  bool _isSuccessUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !_isCheckoutRedirectUri(uri, success: true)) {
      return false;
    }
    return _hasSessionId(uri) || _hasBackendCheckoutSession();
  }

  bool _isCancelUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && _isCheckoutRedirectUri(uri, success: false);
  }

  bool _isCheckoutRedirectUri(Uri uri, {required bool success}) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    if (scheme == 'aveliapp') {
      if (success) {
        return (host == 'checkout' &&
                (path.contains('return') || path.contains('success'))) ||
            host == 'success' ||
            host == 'checkout_success';
      }
      return (host == 'checkout' && path.contains('cancel')) ||
          host == 'cancel' ||
          host == 'checkout_cancel';
    }

    final isAveliHost = host == 'aveli.app' || host.endsWith('.aveli.app');
    final isLocalhost = host == 'localhost' || host == '127.0.0.1';
    if ((scheme == 'https' && isAveliHost) ||
        (scheme == 'http' && isLocalhost)) {
      if (success) {
        return path.contains('checkout/return') || path.endsWith('/success');
      }
      return path.contains('checkout/cancel') || path.endsWith('/cancel');
    }

    return false;
  }

  bool _hasSessionId(Uri uri) {
    final sessionId = uri.queryParameters['session_id'];
    return sessionId != null && sessionId.isNotEmpty;
  }

  bool _hasBackendCheckoutSession() {
    final sessionId = ref.read(checkoutRedirectStateProvider).sessionId;
    return sessionId != null && sessionId.isNotEmpty;
  }

  Future<void> _refreshSession() async {
    if (_refreshed) return;
    _refreshed = true;
    await ref.read(authControllerProvider.notifier).loadSession();
  }

  void _handleCheckoutRedirect(String url) {
    if (_navigatedAway) return;
    _navigatedAway = true;
    Future.microtask(() async {
      final uri = Uri.tryParse(url);
      final success = _isSuccessUrl(url);
      if (uri != null) {
        final handled = await ref.read(deepLinkServiceProvider).handleUri(uri);
        if (handled) return;
      }
      await _refreshSession();
      if (!mounted || !context.mounted) return;
      context.go(_checkoutResultPath(success, uri));
    });
  }

  String _checkoutResultPath(bool success, Uri? uri) {
    if (!success) return RoutePath.checkoutCancel;
    final query = <String, String>{...?uri?.queryParameters};
    final redirectState = ref.read(checkoutRedirectStateProvider);
    if (!query.containsKey('session_id') &&
        redirectState.sessionId != null &&
        redirectState.sessionId!.isNotEmpty) {
      query['session_id'] = redirectState.sessionId!;
    }
    if (!query.containsKey('order_id') &&
        redirectState.orderId != null &&
        redirectState.orderId!.isNotEmpty) {
      query['order_id'] = redirectState.orderId!;
    }
    if (query.isEmpty) return RoutePath.checkoutSuccess;
    return Uri(
      path: RoutePath.checkoutSuccess,
      queryParameters: query,
    ).toString();
  }

  void _ensureWebViewPlatform() {
    if (WebViewPlatform.instance != null) return;
    if (Platform.isAndroid) {
      WebViewPlatform.instance = AndroidWebViewPlatform();
    } else if (Platform.isIOS) {
      WebViewPlatform.instance = WebKitWebViewPlatform();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_embeddedUnavailable) {
      return const AppScaffold(
        title: 'Betalning',
        disableBack: true,
        showHomeAction: false,
        useBasePage: false,
        contentPadding: EdgeInsets.zero,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Inbyggd betalning är inte tillgänglig på den här plattformen. Betalningen öppnas inte utanför appen.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) async {
        await _refreshSession();
        if (!context.mounted) return;
        if (!didPop && !_navigatedAway) {
          Navigator.of(context).pop();
        }
      },
      child: AppScaffold(
        title: 'Betalning',
        showHomeAction: false,
        useBasePage: false,
        contentPadding: EdgeInsets.zero,
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}
