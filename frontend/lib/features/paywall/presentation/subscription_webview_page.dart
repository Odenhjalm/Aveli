import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/paywall/application/entitlements_notifier.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';

class SubscriptionWebViewPage extends ConsumerStatefulWidget {
  const SubscriptionWebViewPage({super.key, required this.url});

  final String url;

  @override
  ConsumerState<SubscriptionWebViewPage> createState() =>
      _SubscriptionWebViewPageState();
}

class _SubscriptionWebViewPageState
    extends ConsumerState<SubscriptionWebViewPage> {
  late final WebViewController _controller;
  bool _refreshed = false;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
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
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (error) {
            final isMainFrame = error.isForMainFrame ?? true;
            if (!mounted || !isMainFrame) return;
            setState(() {
              _hasError = true;
              _isLoading = false;
              _errorMessage = error.description;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
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
    final launched = await launchUrlString(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    if (!launched) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Kunde inte öppna betalningslänk i webbläsare.'),
        ),
      );
    }
    navigator.pop();
  }

  void _returnToSubscription() {
    if (!mounted) return;
    GoRouter.of(context).go(RoutePath.profileSubscription);
  }

  @override
  Widget build(BuildContext context) {
    if (_fallbackExternal) {
      return const AppScaffold(
        title: 'Hantera prenumeration',
        disableBack: true,
        showHomeAction: false,
        useBasePage: false,
        contentPadding: EdgeInsets.zero,
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
        _returnToSubscription();
      },
      child: AppScaffold(
        title: 'Hantera prenumeration',
        showHomeAction: false,
        useBasePage: false,
        contentPadding: EdgeInsets.zero,
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_hasError)
              Positioned.fill(
                child: _PortalErrorView(
                  message: _errorMessage,
                  onRetry: () {
                    setState(() {
                      _hasError = false;
                      _isLoading = true;
                    });
                    _controller.reload();
                  },
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
            if (_isLoading)
              const Positioned.fill(
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _PortalErrorView extends StatelessWidget {
  const _PortalErrorView({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final String? message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final detail = (message ?? '').isNotEmpty
        ? message!
        : 'Stripe-portalen kunde inte laddas. Kontrollera uppkopplingen och försök igen.';

    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            color: colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Kunde inte öppna kundportalen',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    detail,
                    style: textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('Försök igen'),
                  ),
                  TextButton(onPressed: onClose, child: const Text('Stäng')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
