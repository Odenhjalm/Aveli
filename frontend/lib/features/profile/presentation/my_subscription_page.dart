import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/paywall/application/entitlements_notifier.dart';
import 'package:aveli/features/paywall/data/customer_portal_api.dart';
import 'package:aveli/features/paywall/presentation/subscription_webview_page.dart';
import 'package:aveli/shared/widgets/glass_card.dart';

class MySubscriptionPage extends ConsumerStatefulWidget {
  const MySubscriptionPage({super.key});

  @override
  ConsumerState<MySubscriptionPage> createState() => _MySubscriptionPageState();
}

class _MySubscriptionPageState extends ConsumerState<MySubscriptionPage> {
  bool _loadingPortal = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(entitlementsNotifierProvider.notifier).refresh(),
    );
  }

  Color _statusColor(String status, ColorScheme cs) {
    final normalized = status.toLowerCase();
    switch (normalized) {
      case 'active':
        return Colors.green;
      case 'trialing':
        return Colors.blue;
      case 'past_due':
        return Colors.orange;
      case 'canceled':
      case 'incomplete':
      case 'incomplete_expired':
      case 'unpaid':
      case 'unknown':
        return cs.outline;
      default:
        return normalized.isEmpty ? cs.outline : cs.outline;
    }
  }

  String _statusLabel(String status) {
    final normalized = status.toLowerCase();
    switch (normalized) {
      case 'active':
        return 'Aktiv';
      case 'trialing':
        return 'Provperiod';
      case 'past_due':
        return 'Betalning krävs';
      case 'canceled':
        return 'Avslutad';
      case 'unknown':
        return 'Ej aktiv';
      default:
        return normalized.isEmpty ? 'Ej aktiv' : status;
    }
  }

  Future<void> _openPortal() async {
    if (_loadingPortal) return;
    setState(() => _loadingPortal = true);
    try {
      final api = ref.read(customerPortalApiProvider);
      final url = await api.createPortalUrl();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SubscriptionWebViewPage(url: url),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final detail = _formatError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kunde inte öppna kundportal: $detail'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingPortal = false);
      }
    }
  }

  String _formatError(Object error) {
    final value = error.toString();
    const prefix = 'Exception: ';
    if (value.startsWith(prefix)) {
      return value.substring(prefix.length);
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(entitlementsNotifierProvider);
    final data = state.data;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final membership = data?.membership;
    final rawStatus = membership?.status ?? 'unknown';
    final status = rawStatus.isEmpty ? 'unknown' : rawStatus;
    final isUnknownStatus = status.toLowerCase() == 'unknown';
    final nextBilling = membership?.nextBillingAt;
    final statusColor = _statusColor(status, cs);
    final isTrial = status.toLowerCase() == 'trialing';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(RoutePath.profile);
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () => context.go('/'),
          ),
        ],
        title: const Text(
          'Min prenumeration',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          opacity: 0.2,
          borderRadius: BorderRadius.circular(20),
          borderColor: Colors.white.withValues(alpha: 0.18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Medlemskap Aveli',
                          style: t.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Få tillgång till allt premiuminnehåll.',
                          style: t.bodyMedium?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    backgroundColor: statusColor.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                    label: Text(_statusLabel(status)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isTrial)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '14 dagars gratis provperiod',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (nextBilling != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Nästa debitering: '
                  '${MaterialLocalizations.of(context).formatFullDate(nextBilling.toLocal())}',
                  style: t.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Hantera prenumeration',
                style: t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isUnknownStatus
                    ? 'Starta och hantera betalningsuppgifter i Stripe-portalen.'
                    : 'Byt plan, avsluta, uppdatera betalningar och hitta kvitton direkt i kundportalen.',
                style: t.bodyMedium?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: state.loading || _loadingPortal ? null : _openPortal,
                child: _loadingPortal
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Hantera prenumeration'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () =>
                      ref.read(entitlementsNotifierProvider.notifier).refresh(),
                  child: const Text('Uppdatera status'),
                ),
              ),
              if (state.loading) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(minHeight: 2),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
