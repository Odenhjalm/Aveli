// ignore_for_file: uri_does_not_exist, avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

const bool supportsEmbeddedMembershipCheckout = true;

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
  late final String _viewType =
      'aveli-embedded-membership-checkout-${DateTime.now().microsecondsSinceEpoch}';
  late final String _mountId =
      'aveli-stripe-checkout-${DateTime.now().microsecondsSinceEpoch}';

  late final html.DivElement _root;
  late final html.DivElement _status;
  late final html.DivElement _mount;
  bool _mountStarted = false;
  bool _completionHandled = false;

  @override
  void initState() {
    super.initState();
    _root = _buildRoot();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _root);
    WidgetsBinding.instance.addPostFrameCallback((_) => _mountStripeCheckout());
  }

  @override
  void didUpdateWidget(covariant EmbeddedMembershipCheckoutSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientSecret != widget.clientSecret ||
        oldWidget.stripePublishableKey != widget.stripePublishableKey) {
      _mountStarted = false;
      _completionHandled = false;
      _status
        ..text = 'Betalningspanelen laddas.'
        ..classes.remove('error');
      _mount.children.clear();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _mountStripeCheckout(),
      );
    }
  }

  html.DivElement _buildRoot() {
    final root = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.minHeight = '680px'
      ..style.backgroundColor = 'transparent'
      ..style.border = '0'
      ..style.borderRadius = '8px'
      ..style.overflowX = 'hidden'
      ..style.overflowY = 'auto';
    root.style.setProperty('-webkit-overflow-scrolling', 'touch');
    root.style.setProperty('scrollbar-gutter', 'stable');

    _status = html.DivElement()
      ..text = 'Betalningspanelen laddas.'
      ..style.padding = '18px'
      ..style.color = '#5d6876'
      ..style.fontFamily =
          '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'
      ..style.fontSize = '15px'
      ..style.lineHeight = '1.5';

    _mount = html.DivElement()
      ..id = _mountId
      ..style.width = '100%'
      ..style.minHeight = '680px';

    root.children.add(_status);
    root.children.add(_mount);
    return root;
  }

  Future<void> _mountStripeCheckout() async {
    if (_mountStarted || !mounted) return;
    _mountStarted = true;
    if (widget.stripePublishableKey.trim().isEmpty) {
      _showDomError(
        'Stripe-konfiguration saknas. Betalningen kan inte starta ännu.',
      );
      return;
    }
    if (widget.clientSecret.trim().isEmpty) {
      _showDomError('Betalningssessionen saknas. Försök igen.');
      return;
    }

    try {
      await _loadStripeJs();
      final stripe = js_util.callMethod<Object>(html.window, 'Stripe', [
        widget.stripePublishableKey,
      ]);
      final options = js_util.newObject<Object>();
      js_util.setProperty(
        options,
        'fetchClientSecret',
        (() => widget.clientSecret).toJS,
      );
      js_util.setProperty(options, 'onComplete', _handleCheckoutComplete.toJS);
      final checkoutPromise = js_util.callMethod<Object>(
        stripe,
        'initEmbeddedCheckout',
        [options],
      );
      final checkout = await js_util.promiseToFuture<Object>(checkoutPromise);
      _status.remove();
      js_util.callMethod<Object>(checkout, 'mount', ['#$_mountId']);
    } catch (_) {
      _showDomError(
        'Betalningspanelen kunde inte laddas. Försök igen om en stund.',
      );
    }
  }

  Future<void> _loadStripeJs() {
    if (js_util.hasProperty(html.window, 'Stripe')) {
      return Future<void>.value();
    }

    final completer = Completer<void>();
    final script = html.ScriptElement()
      ..src = 'https://js.stripe.com/v3/'
      ..async = true;

    script.onLoad.first.then((_) {
      if (!completer.isCompleted) completer.complete();
    });
    script.onError.first.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Stripe.js load failed'));
      }
    });
    html.document.head?.append(script);
    return completer.future;
  }

  void _handleCheckoutComplete() {
    if (_completionHandled || !mounted) return;
    _completionHandled = true;
    widget.onCheckoutRedirect(_successUri());
  }

  Uri _successUri() {
    return Uri(
      scheme: 'aveliapp',
      host: 'checkout',
      path: '/return',
      queryParameters: {
        if (widget.sessionId.isNotEmpty) 'session_id': widget.sessionId,
        if (widget.orderId.isNotEmpty) 'order_id': widget.orderId,
      },
    );
  }

  void _showDomError(String message) {
    _status
      ..text = message
      ..classes.add('error')
      ..style.color = '#8a2130'
      ..style.backgroundColor = '#fff4f6'
      ..style.borderBottom = '1px solid #ffd9e0';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
