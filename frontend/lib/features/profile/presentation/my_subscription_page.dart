import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/glass_card.dart';

class MySubscriptionPage extends ConsumerStatefulWidget {
  const MySubscriptionPage({super.key});

  @override
  ConsumerState<MySubscriptionPage> createState() => _MySubscriptionPageState();
}

class _MySubscriptionPageState extends ConsumerState<MySubscriptionPage> {
  bool _refreshing = false;

  Future<void> _refreshMembershipState() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(authControllerProvider.notifier).loadSession();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sessionen uppdaterades. Åtkomst avgörs alltid av medlemsstatusen på servern.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AppScaffold(
      title: 'Mitt medlemskap',
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
                'Appen ändrar inte medlemskap direkt och använder inte betalstatus som åtkomstbeslut.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 20),
              Text(
                'Uppdatera medlemsstatus',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Om du precis har betalat kan du uppdatera din session här. Medlemsstatusen på servern avgör alltid åtkomsten.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _refreshing ? null : _refreshMembershipState,
                child: _refreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Uppdatera medlemskap'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
