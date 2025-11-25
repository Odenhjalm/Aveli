import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisdom/core/errors/app_failure.dart';
import 'package:wisdom/core/routing/app_routes.dart';
import 'package:wisdom/core/routing/route_paths.dart';
import 'package:wisdom/features/community/application/community_providers.dart';
import 'package:wisdom/data/models/service.dart';
import 'package:wisdom/core/routing/route_session.dart';
import 'package:wisdom/shared/utils/snack.dart';
import 'package:wisdom/shared/widgets/app_scaffold.dart';
import 'package:wisdom/features/community/application/certification_gate.dart';
import 'package:wisdom/features/paywall/data/checkout_api.dart';

class ServiceDetailPage extends ConsumerStatefulWidget {
  const ServiceDetailPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ServiceDetailPage> createState() => _ServiceDetailPageState();
}

class _ServiceDetailPageState extends ConsumerState<ServiceDetailPage> {
  bool _buying = false;

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
        final certsAsync = ref.watch(myCertificatesProvider);
        final gate = evaluateCertificationGate(
          service: service,
          viewerCertificates: certsAsync,
          isAuthenticated: session.isAuthenticated,
        );
        final t = Theme.of(context).textTheme;
        final title = service.title;
        final desc = service.description;
        final price = service.priceCents / 100.0;
        final buttonBusy = _buying || gate.pending;
        final buttonLabel = gate.pending
            ? 'Kontrollerar behörighet...'
            : gate.requiresAuth
            ? 'Logga in för att boka'
            : gate.allowed
            ? 'Boka/Köp'
            : 'Certifiering krävs';
        final onPressed = gate.pending
            ? null
            : gate.requiresAuth
            ? _goToLogin
            : gate.allowed && !_buying
            ? () => _buy(service)
            : null;
        final buttonChild = buttonBusy
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
                          ElevatedButton(
                            onPressed: onPressed,
                            child: buttonChild,
                          ),
                        ],
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

  Future<void> _buy(Service service) async {
    final gate = evaluateCertificationGate(
      service: service,
      viewerCertificates: ref.read(myCertificatesProvider),
      isAuthenticated: ref.read(routeSessionSnapshotProvider).isAuthenticated,
    );
    if (!gate.allowed) {
      if (gate.requiresAuth) {
        _goToLogin();
      } else if (gate.message != null) {
        _showSnack(gate.message!);
      } else if (gate.pending) {
        _showSnack('Vänta tills behörigheten har kontrollerats.');
      }
      return;
    }
    final price = service.priceCents;
    final id = service.id;
    if (price <= 0) {
      _showSnack('Tjänsten saknar pris och kan inte bokas just nu.');
      return;
    }
    setState(() => _buying = true);
    try {
      final checkoutApi = ref.read(checkoutApiProvider);
      final url = await checkoutApi.startServiceCheckout(serviceId: id);
      if (!mounted) return;
      context.push(RoutePath.checkout, extra: url);
    } catch (error) {
      _showSnack('Kunde inte initiera köp: ${_friendlyError(error)}');
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    showSnack(context, message);
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
