import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/features/paywall/application/checkout_flow.dart';
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
    final redirectState = ref.watch(checkoutRedirectStateProvider);
    final query = GoRouterState.of(context).uri.queryParameters;
    final sessionId = query['session_id'] ?? redirectState.sessionId;
    final orderId = query['order_id'] ?? redirectState.orderId;
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
                            'Frontend väntar på backend-bekräftelse innan åtkomst uppdateras.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium,
                      ),
                      if (sessionId != null || orderId != null) ...[
                        gap16,
                        if (sessionId != null)
                          Text(
                            'session_id: $sessionId',
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall,
                          ),
                        if (orderId != null)
                          Text(
                            'order_id: $orderId',
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall,
                          ),
                      ],
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
    final currentRedirect = ref.read(checkoutRedirectStateProvider);
    ref.read(checkoutRedirectStateProvider.notifier).state = currentRedirect
        .copyWith(
          status: widget.success
              ? CheckoutRedirectStatus.success
              : CheckoutRedirectStatus.canceled,
          clearError: true,
        );

    if (!mounted) return;
    setState(() {
      _isRefreshing = false;
      _message = widget.success
          ? 'Vi har uppdaterat din backend-session. Åtkomst visas först när webhooken har bekräftat köpet.'
          : 'Ingen åtkomst ändras på frontend när checkout avbryts.';
    });
  }
}
