import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/payments/application/payments_providers.dart';
import 'package:aveli/features/paywall/application/entitlements_notifier.dart';
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
  bool _loading = false;
  String? _statusMessage;
  String? _errorMessage;
  String? _activeSubscriptionId;
  String? _latestStatus;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    if (!config.subscriptionsEnabled) {
      return const AppScaffold(
        title: 'Abonnemang',
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Prenumerationer är inte aktiverade ännu. '
                  'Vi uppdaterar roadmapen när medlemskap ersätter traditionella subscription-flöden.',
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
    final subscriptionAsync = ref.watch(activeSubscriptionProvider);
    final activeSubscription = subscriptionAsync.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );

    final effectiveSubscriptionId =
        _activeSubscriptionId ??
        activeSubscription?['subscription_id'] as String?;
    final effectiveStatus =
        _latestStatus ?? activeSubscription?['status'] as String? ?? 'okänd';

    final envBlocked = envInfo.hasIssues;
    void cancelSubscription() {
      final id = effectiveSubscriptionId;
      if (envBlocked || _loading || id == null || authState.profile == null) {
        return;
      }
      _cancelSubscription(id);
    }

    return AppScaffold(
      title: 'Abonnemang',
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
                          '${envInfo.message} Abonnemang är avstängt tills konfigurationen är klar.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    if (authState.profile == null)
                      _LoginPrompt(onRequestLogin: _redirectToLogin)
                    else
                      _SubscriptionStatusBadge(
                        status: effectiveStatus,
                        subscriptionId: effectiveSubscriptionId,
                        loading: subscriptionAsync.isLoading,
                      ),
                    gap16,
                    Text(
                      'Bli medlem',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    gap12,
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    if (_statusMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _statusMessage!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    GradientButton(
                      onPressed: envBlocked || _loading
                          ? null
                          : () => _startSubscription(authState.profile),
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Bli medlem'),
                    ),
                    const SizedBox(height: 12),
                    GradientButton.tonal(
                      onPressed:
                          envBlocked ||
                              _loading ||
                              effectiveSubscriptionId == null ||
                              authState.profile == null
                          ? null
                          : cancelSubscription,
                      child: const Text('Avbryt prenumeration'),
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

  Future<void> _startSubscription(Profile? profile) async {
    if (profile == null) {
      _redirectToLogin();
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _statusMessage = null;
    });

    try {
      final checkoutApi = ref.read(checkoutApiProvider);
      final url = await checkoutApi.startMembershipCheckout(interval: 'month');
      if (!mounted) return;
      context.push(RoutePath.checkout, extra: url);
      _statusMessage = 'Öppnar betalning...';
    } catch (error, stackTrace) {
      final failure = AppFailure.from(error, stackTrace);
      if (failure.kind == AppFailureKind.unauthorized) {
        _redirectToLogin();
        return;
      }
      setState(() {
        _errorMessage = failure.message;
        _statusMessage = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _cancelSubscription(String subscriptionId) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(paymentsRepositoryProvider);
      await repo.cancelSubscription(subscriptionId);
      _statusMessage =
          'Prenumerationen avbröts. Du har fortsatt tillgång tills perioden löper ut.';
      _latestStatus = 'canceled';
      // Uppdatera medlemskapsstatusen direkt i UI:t när backend har stängt prenumerationen.
      await ref.read(entitlementsNotifierProvider.notifier).refresh();
      ref.invalidate(activeSubscriptionProvider);
    } on AppFailure catch (failure) {
      setState(() {
        _errorMessage = failure.message;
      });
    } catch (error, stackTrace) {
      setState(() {
        _errorMessage = AppFailure.from(error, stackTrace).message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _redirectToLogin() {
    if (!mounted) return;
    final redirect = GoRouter.of(context).namedLocation(AppRoute.subscribe);
    context.goNamed(AppRoute.login, queryParameters: {'redirect': redirect});
  }
}

class _SubscriptionStatusBadge extends StatelessWidget {
  const _SubscriptionStatusBadge({
    required this.status,
    required this.subscriptionId,
    required this.loading,
  });

  final String status;
  final String? subscriptionId;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final statusLabel = switch (normalized) {
      'active' => 'Aktiv',
      'trialing' => 'Provperiod',
      'past_due' => 'Betalning krävs',
      'canceled' || 'cancelled' => 'Avslutad',
      'incomplete' || 'incomplete_expired' => 'Ej färdigställd',
      'unpaid' => 'Obetald',
      _ => status.isEmpty ? 'Okänd' : status.toUpperCase(),
    };
    final label = subscriptionId == null
        ? 'Ingen aktiv prenumeration'
        : 'Status: $statusLabel (ID: $subscriptionId)';
    final color = subscriptionId == null
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).colorScheme.primary;
    return Card(
      color: color.withValues(alpha: 0.08),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              subscriptionId == null ? Icons.info_outline : Icons.verified_user,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (loading)
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
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
            const Text(
              'Du behöver ett konto för att starta eller hantera din prenumeration.',
            ),
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
