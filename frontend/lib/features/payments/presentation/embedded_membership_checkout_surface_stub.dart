import 'package:flutter/material.dart';

const bool supportsEmbeddedMembershipCheckout = false;

class EmbeddedMembershipCheckoutSurface extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return const _UnsupportedEmbeddedCheckoutMessage();
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
