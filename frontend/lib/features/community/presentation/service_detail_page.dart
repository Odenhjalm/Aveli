import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/core/routing/route_session.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/features/community/application/certification_gate.dart';

class ServiceDetailPage extends ConsumerStatefulWidget {
  const ServiceDetailPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ServiceDetailPage> createState() => _ServiceDetailPageState();
}

class _ServiceDetailPageState extends ConsumerState<ServiceDetailPage> {
  @override
  Widget build(BuildContext context) {
    final serviceAsync = ref.watch(serviceDetailProvider(widget.id));
    return serviceAsync.when(
      loading: () => const AppScaffold(
        title: 'Tjänst',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AppScaffold(
        title: 'Tjänst',
        body: Center(child: Text(_friendlyError(error))),
      ),
      data: (state) {
        final service = state.service;
        if (service == null) {
          return const AppScaffold(
            title: 'Tjänst',
            body: Center(child: Text('Tjänst hittades inte')),
          );
        }
        final provider = state.provider;
        final session = ref.watch(routeSessionSnapshotProvider);
        final gate = evaluateCertificationGate(
          service: service,
          isAuthenticated: session.isAuthenticated,
        );
        final t = Theme.of(context).textTheme;
        final title = service.title;
        final desc = service.description;
        final price = service.priceCents / 100.0;
        final buttonLabel = gate.pending
            ? 'Kontrollerar behörighet...'
            : gate.requiresAuth
            ? 'Logga in'
            : 'Certifiering krävs';
        final onPressed = gate.pending
            ? null
            : gate.requiresAuth
            ? _goToLogin
            : null;
        final buttonChild = gate.pending
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : (!gate.allowed && !gate.pending)
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_rounded, size: 18),
                  const SizedBox(width: 6),
                  Text(buttonLabel),
                ],
              )
            : Text(buttonLabel);

        return AppScaffold(
          title: title,
          body: ListView(
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_rounded),
                  title: Text(provider?['display_name'] as String? ?? 'Lärare'),
                  subtitle: const Text('Leverantör'),
                  onTap: () {
                    final id = provider?['user_id'] as String?;
                    if (id != null) {
                      context.pushNamed(
                        AppRoute.profileView,
                        pathParameters: {'id': id},
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: t.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(desc, style: t.bodyMedium),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            '${price.toStringAsFixed(2)} kr',
                            style: t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          if (onPressed != null)
                            ElevatedButton(
                              onPressed: onPressed,
                              child: buttonChild,
                            ),
                        ],
                      ),
                      if (gate.allowed)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'Bokning är inte tillgänglig i appen just nu.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      if (gate.message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            gate.message!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _friendlyError(Object error) => AppFailure.from(error).message;

  void _goToLogin() {
    if (!mounted) return;
    final router = GoRouter.of(context);
    final redirectTarget = GoRouterState.of(context).uri.toString();
    router.goNamed(
      AppRoute.login,
      queryParameters: {'redirect': redirectTarget},
    );
  }
}
