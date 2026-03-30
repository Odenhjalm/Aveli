import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/paywall/data/customer_portal_api.dart';
import 'package:aveli/features/paywall/presentation/subscription_webview_page.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/glass_card.dart';

class MySubscriptionPage extends ConsumerStatefulWidget {
  const MySubscriptionPage({super.key});

  @override
  ConsumerState<MySubscriptionPage> createState() => _MySubscriptionPageState();
}

class _MySubscriptionPageState extends ConsumerState<MySubscriptionPage> {
  bool _loadingPortal = false;

  Future<void> _openPortal() async {
    if (_loadingPortal) return;
    setState(() => _loadingPortal = true);
    try {
      final api = ref.read(customerPortalApiProvider);
      final url = await api.createPortalUrl();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SubscriptionWebViewPage(url: url)),
      );
    } catch (e) {
      if (!mounted) return;
      final detail = _formatError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte öppna kundportal: $detail')),
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
    final t = Theme.of(context).textTheme;

    return AppScaffold(
      title: 'Min prenumeration',
      showHomeAction: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => context.go(RoutePath.landingRoot),
        ),
      ],
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
              Text(
                'Medlemskap Aveli',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                'Prenumerationsstatus visas inte längre i appen. Använd kundportalen för betalningsärenden när den är tillgänglig.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 20),
              Text(
                'Hantera prenumeration',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Öppna kundportalen för att uppdatera betalningsuppgifter och hantera din prenumeration.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loadingPortal ? null : _openPortal,
                child: _loadingPortal
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Hantera prenumeration'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
