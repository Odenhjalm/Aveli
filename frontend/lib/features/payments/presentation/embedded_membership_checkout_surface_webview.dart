import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'embedded_checkout_html.dart';

final bool supportsEmbeddedMembershipCheckout =
    !Platform.isLinux && !Platform.isWindows;

class EmbeddedMembershipCheckoutSurface extends StatefulWidget {
  const EmbeddedMembershipCheckoutSurface({
    super.key,
    required this.stripePublishableKey,
    required this.clientSecret,
    required this.sessionId,
    required this.orderId,
    required this.onCheckoutRedirect,
  });

  final String stripePublishableKey;
  final String clientSecret;
  final String sessionId;
  final String orderId;
  final ValueChanged<Uri> onCheckoutRedirect;

  @override
  State<EmbeddedMembershipCheckoutSurface> createState() =>
      _EmbeddedMembershipCheckoutSurfaceState();
}

class _EmbeddedMembershipCheckoutSurfaceState
    extends State<EmbeddedMembershipCheckoutSurface> {
  WebViewController? _controller;
  bool _navigatedAway = false;

  @override
  void initState() {
    super.initState();
    _configureController();
  }

  @override
  void didUpdateWidget(covariant EmbeddedMembershipCheckoutSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientSecret != widget.clientSecret ||
        oldWidget.stripePublishableKey != widget.stripePublishableKey) {
      _navigatedAway = false;
      _loadCheckoutHtml();
    }
  }

  void _configureController() {
    if (!supportsEmbeddedMembershipCheckout) return;
    _ensureWebViewPlatform();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && _isCheckoutRedirectUri(uri)) {
              _handleRedirect(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
    _loadCheckoutHtml();
  }

  void _loadCheckoutHtml() {
    final controller = _controller;
    if (controller == null) return;
    controller.loadHtmlString(
      buildEmbeddedCheckoutHtml(
        stripePublishableKey: widget.stripePublishableKey,
        clientSecret: widget.clientSecret,
      ),
      baseUrl: 'https://aveli.app',
    );
  }

  void _handleRedirect(Uri uri) {
    if (_navigatedAway) return;
    _navigatedAway = true;
    widget.onCheckoutRedirect(uri);
  }

  bool _isCheckoutRedirectUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    if (scheme == 'aveliapp') {
      return host == 'success' ||
          host == 'cancel' ||
          host == 'checkout_success' ||
          host == 'checkout_cancel' ||
          (host == 'checkout' &&
              (path.contains('return') || path.contains('cancel')));
    }

    final isAveliHost = host == 'aveli.app' || host.endsWith('.aveli.app');
    final isLocalhost = host == 'localhost' || host == '127.0.0.1';
    if ((scheme == 'https' && isAveliHost) ||
        (scheme == 'http' && isLocalhost)) {
      return path.contains('checkout/return') ||
          path.contains('checkout/cancel') ||
          path.endsWith('/success') ||
          path.endsWith('/cancel');
    }

    return false;
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
    final controller = _controller;
    if (!supportsEmbeddedMembershipCheckout || controller == null) {
      return const _UnsupportedEmbeddedCheckoutMessage();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: WebViewWidget(controller: controller),
    );
  }
}

class _UnsupportedEmbeddedCheckoutMessage extends StatelessWidget {
  const _UnsupportedEmbeddedCheckoutMessage();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'Inbyggd betalning är inte tillgänglig på den här plattformen.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
