import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/paywall/application/entitlements_notifier.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';

class CheckoutReturnPage extends ConsumerStatefulWidget {
  const CheckoutReturnPage({super.key, required this.sessionId});

  final String? sessionId;

  @override
  ConsumerState<CheckoutReturnPage> createState() => _CheckoutReturnPageState();
}

class _CheckoutReturnPageState extends ConsumerState<CheckoutReturnPage> {
  CheckoutVerificationResult? _result;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_verifyCheckout);
  }

  Future<void> _verifyCheckout() async {
    final sessionId = (widget.sessionId ?? '').trim();
    if (sessionId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'session_id saknas i retur-URL.';
      });
      return;
    }

    try {
      final result = await ref
          .read(checkoutApiProvider)
          .verifyCheckoutSession(sessionId: sessionId);
      if (result.success) {
        await ref.read(entitlementsNotifierProvider.notifier).refresh();
      }
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  String _resultMessage(CheckoutVerificationResult result) {
    if (result.success) {
      return 'Betalningen är bekräftad. Ditt köp är nu aktivt.';
    }
    switch (result.status) {
      case 'canceled':
        return 'Checkout avbröts innan betalningen slutfördes.';
      case 'pending':
        return 'Betalningen behandlas fortfarande. Prova att uppdatera om en stund.';
      default:
        return 'Betalningen kunde inte verifieras.';
    }
  }

  void _goHome() {
    context.go(RoutePath.home);
  }

  void _goToCourse(String slug) {
    context.go(RoutePath.courseWithSlug(slug));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppScaffold(
        title: 'Checkout',
        disableBack: true,
        showHomeAction: false,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return AppScaffold(
        title: 'Checkout',
        showHomeAction: false,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Kunde inte verifiera checkout.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton(
                      onPressed: _verifyCheckout,
                      child: const Text('Försök igen'),
                    ),
                    OutlinedButton(
                      onPressed: _goHome,
                      child: const Text('Till startsidan'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final result = _result!;
    final success = result.success;
    final statusColor = success ? Colors.green : Colors.orange;
    final icon = success ? Icons.check_circle_outline : Icons.info_outline;

    return AppScaffold(
      title: 'Checkout',
      showHomeAction: false,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: statusColor),
              const SizedBox(height: 12),
              Text(
                success ? 'Betalning klar' : 'Checkout uppdaterad',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(_resultMessage(result), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Session: ${result.sessionId}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (success &&
                      result.courseSlug != null &&
                      result.courseSlug!.isNotEmpty)
                    FilledButton(
                      onPressed: () => _goToCourse(result.courseSlug!),
                      child: const Text('Öppna kurs'),
                    ),
                  if (!success)
                    FilledButton(
                      onPressed: _verifyCheckout,
                      child: const Text('Verifiera igen'),
                    ),
                  OutlinedButton(
                    onPressed: _goHome,
                    child: const Text('Till startsidan'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
