import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class CheckoutResultPage extends ConsumerStatefulWidget {
  const CheckoutResultPage({super.key, required this.success});

  final bool success;

  @override
  ConsumerState<CheckoutResultPage> createState() => _CheckoutResultPageState();
}

class _CheckoutResultPageState extends ConsumerState<CheckoutResultPage> {
  bool _isRefreshing = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshBootstrap());
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppScaffold(
      title: '',
      disableBack: true,
      showHomeAction: false,
      useBasePage: false,
      contentPadding: EdgeInsets.zero,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: p16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isRefreshing) ...[
                      const Center(child: CircularProgressIndicator()),
                      gap24,
                      Text(
                        widget.success
                            ? 'Bekraftar din betalning...'
                            : 'Uppdaterar ditt konto...',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyLarge,
                      ),
                    ] else ...[
                      Text(
                        widget.success
                            ? 'Vi vantar fortfarande pa betalningsbekraftelse'
                            : 'Betalningen avbrots',
                        textAlign: TextAlign.center,
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      gap16,
                      Text(
                        _message ??
                            'Uppdatera sidan igen sa fort Stripe har hunnit skicka webhooken.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium,
                      ),
                      gap24,
                      GradientButton(
                        onPressed: _refreshBootstrap,
                        child: const Text('Kontrollera igen'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refreshBootstrap() async {
    if (mounted) {
      setState(() {
        _isRefreshing = true;
        _message = null;
      });
    }

    final authController = ref.read(authControllerProvider.notifier);
    await authController.loadSession();

    if (!mounted) return;
    setState(() {
      _isRefreshing = false;
      _message = widget.success
          ? 'Betalningen registreras just nu. Kontrollera igen om din åtkomst inte har uppdaterats ännu.'
          : null;
    });
  }
}
