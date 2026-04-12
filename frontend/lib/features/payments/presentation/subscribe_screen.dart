import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/paywall/application/checkout_flow.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class SubscribeScreen extends ConsumerStatefulWidget {
  const SubscribeScreen({super.key});

  @override
  ConsumerState<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends ConsumerState<SubscribeScreen> {
  String? _submittingInterval;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    if (!config.subscriptionsEnabled) {
      return const AppScaffold(
        title: 'Medlemskap',
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Medlemskap är inte aktiverat ännu. När launch-flödet öppnas här används bara det kanoniska backend-checkoutflödet.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final envInfo = ref.watch(envInfoProvider);
    final authState = ref.watch(authControllerProvider);
    final entryState = authState.entryState;
    final envBlocked = envInfo.hasIssues;

    return AppScaffold(
      title: 'Medlemskap',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: p16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (envBlocked)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          '${envInfo.message} Medlemsköp är avstängt tills konfigurationen är klar.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    if (entryState == null)
                      _LoginPrompt(onRequestLogin: _redirectToLogin)
                    else
                      Card(
                        elevation: 0,
                        color: Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: 0.08),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Checkout startas via backend och åtkomst uppdateras först efter webhook-bekräftelse.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.secondary,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    gap16,
                    Text(
                      'Bli medlem',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    gap12,
                    const Text(
                      'Frontend startar bara checkout och visar Stripe-sidan. Medlemsstatus och åtkomst bekräftas alltid av backend efter webhooken.',
                    ),
                    gap16,
                    if (entryState?.needsPayment == true)
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _IntervalButton(
                            label: 'Månadsmedlemskap',
                            busy: _submittingInterval == 'month',
                            enabled: !envBlocked && _submittingInterval == null,
                            onPressed: () => _startMembershipCheckout('month'),
                          ),
                          _IntervalButton(
                            label: 'Årsmedlemskap',
                            busy: _submittingInterval == 'year',
                            enabled: !envBlocked && _submittingInterval == null,
                            onPressed: () => _startMembershipCheckout('year'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startMembershipCheckout(String interval) async {
    if (_submittingInterval != null) return;
    final router = GoRouter.of(context);
    final returnPath = GoRouterState.of(context).uri.toString();
    setState(() => _submittingInterval = interval);
    try {
      final api = ref.read(checkoutApiProvider);
      final launch = await api.createMembershipCheckout(interval: interval);
      ref.read(checkoutContextProvider.notifier).state = CheckoutContext(
        type: CheckoutItemType.membership,
        returnPath: returnPath,
      );
      ref
          .read(checkoutRedirectStateProvider.notifier)
          .state = CheckoutRedirectState(
        status: CheckoutRedirectStatus.processing,
        sessionId: launch.sessionId,
        orderId: launch.orderId,
      );
      if (!mounted) return;
      router.pushNamed(AppRoute.checkout, extra: launch.url);
    } catch (error, stackTrace) {
      if (!mounted) return;
      final failure = AppFailure.from(error, stackTrace);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) {
        setState(() => _submittingInterval = null);
      }
    }
  }

  void _redirectToLogin() {
    if (!mounted) return;
    final redirect = GoRouter.of(context).namedLocation(AppRoute.subscribe);
    context.goNamed(AppRoute.login, queryParameters: {'redirect': redirect});
  }
}

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt({required this.onRequestLogin});

  final VoidCallback onRequestLogin;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(
        context,
      ).colorScheme.errorContainer.withValues(alpha: 0.2),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Logga in för att fortsätta',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            gap8,
            const Text('Du behöver ett konto för att starta medlemscheckout.'),
            gap12,
            GradientButton(
              onPressed: onRequestLogin,
              child: const Text('Logga in'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntervalButton extends StatelessWidget {
  const _IntervalButton({
    required this.label,
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: GradientButton(
        onPressed: enabled ? onPressed : null,
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }
}
