import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:aveli/features/paywall/application/entitlements_notifier.dart';

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
  bool _fallbackExternal = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb || (!kIsWeb && Platform.isLinux)) {
      _fallbackExternal = true;
      Future.microtask(_openExternally);
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
              _refreshEntitlements();
              Navigator.of(context).pop();
              return NavigationDecision.prevent;
            }
            if (_isCancelUrl(url)) {
              Navigator.of(context).pop();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  // Stripe skickar både custom schemes (aveliapp://checkout_success) och https-länkar tillbaka.
  // Vi matchar båda så att modalen alltid stängs även när Safari/Chrome hoppar bort från WebView.
  bool _isSuccessUrl(String url) {
    final normalized = url.toLowerCase();
    return normalized.contains('checkout/return') ||
        (normalized.contains('session_id=') && normalized.contains('checkout/return')) ||
        normalized.contains('/success') ||
        (normalized.startsWith('http://localhost') && normalized.contains('/success')) ||
        normalized.startsWith('aveliapp://success') ||
        normalized.startsWith('aveliapp://checkout/return') ||
        normalized.startsWith('aveliapp://checkout/success') ||
        normalized.startsWith('aveliapp://checkout_success') ||
        normalized.contains('checkout_success=true') ||
        normalized.contains('checkout_success') ||
        normalized.contains('checkout/success');
  }

  // Samma gäller cancel-urlen – backend skickar ibland checkout_cancel och ibland HTTPS-varianter.
  bool _isCancelUrl(String url) {
    final normalized = url.toLowerCase();
    return normalized.contains('/cancel') ||
        normalized.startsWith('http://localhost') && normalized.contains('/cancel') ||
        normalized.startsWith('aveliapp://cancel') ||
        normalized.startsWith('aveliapp://checkout/cancel') ||
        normalized.startsWith('aveliapp://checkout_cancel') ||
        normalized.contains('checkout_cancel=true') ||
        normalized.contains('checkout_cancel') ||
        normalized.contains('checkout/cancel');
  }

  Future<void> _refreshEntitlements() async {
    if (_refreshed) return;
    _refreshed = true;
    await ref.read(entitlementsNotifierProvider.notifier).refresh();
  }

  void _ensureWebViewPlatform() {
    if (WebViewPlatform.instance != null) return;
    if (Platform.isAndroid) {
      WebViewPlatform.instance = AndroidWebViewPlatform();
    } else if (Platform.isIOS) {
      WebViewPlatform.instance = WebKitWebViewPlatform();
    }
  }

  Future<void> _openExternally() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final url = widget.url;
    final launched =
        await launchUrlString(url, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Kunde inte öppna betalningslänk i webbläsare.')),
      );
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_fallbackExternal) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) async {
        await _refreshEntitlements();
        if (!context.mounted) return;
        if (!didPop) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Betalning'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}
