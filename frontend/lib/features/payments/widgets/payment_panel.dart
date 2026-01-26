import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/widgets/glass_container.dart';

class PaymentPanel extends StatefulWidget {
  const PaymentPanel({
    super.key,
    required this.clientSecret,
    required this.onPaymentSuccess,
    this.onCancelled,
  });

  final String clientSecret;
  final VoidCallback onPaymentSuccess;
  final VoidCallback? onCancelled;

  @override
  State<PaymentPanel> createState() => _PaymentPanelState();
}

class _PaymentPanelState extends State<PaymentPanel> {
  CardFieldInputDetails? _cardDetails;
  bool _processing = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final isReady = (_cardDetails?.complete ?? false) && !_processing;
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Säker betalning',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Kort, wallets, PayPal och Klarna hanteras via Stripe Payment Element.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: const [
                _MethodChip(label: 'Visa'),
                _MethodChip(label: 'Mastercard'),
                _MethodChip(label: 'PayPal'),
                _MethodChip(label: 'Klarna'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CardField(
            style: Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
            cursorColor: Theme.of(context).colorScheme.onSurface,
            decoration: InputDecoration(
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
            onCardChanged: (details) => setState(() => _cardDetails = details),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: GradientButton(
                  onPressed: isReady ? _confirmPayment : null,
                  child: _processing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Boka & betala'),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _processing
                    ? null
                    : () {
                        widget.onCancelled?.call();
                        Navigator.of(context).maybePop();
                      },
                child: const Text('Avbryt'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPayment() async {
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: widget.clientSecret,
        data: const PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(),
        ),
      );
      if (!mounted) return;
      widget.onPaymentSuccess();
    } on StripeException catch (error) {
      setState(() {
        _error = error.error.message ?? 'Betalningen misslyckades.';
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.adjust, size: 12),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
