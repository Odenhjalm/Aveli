import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisdom/core/auth/auth_controller.dart';
import 'package:wisdom/core/routing/app_routes.dart';
import 'package:wisdom/features/paywall/application/entitlements_notifier.dart';
import 'package:wisdom/features/paywall/data/checkout_api.dart';
import 'package:wisdom/core/routing/route_paths.dart';

class PaywallGate extends ConsumerWidget {
  const PaywallGate({
    super.key,
    required this.courseSlug,
    required this.unlocked,
    this.lockedOverride,
  });

  final String courseSlug;
  final Widget unlocked;
  final Widget? lockedOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(entitlementsNotifierProvider);
    final notifier = ref.read(entitlementsNotifierProvider.notifier);
    final authState = ref.watch(authControllerProvider);

    if (state.loading && state.data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final hasMembership = notifier.membershipActive;
    final hasCourse = notifier.hasCourse(courseSlug);

    if (hasMembership || hasCourse) {
      return unlocked;
    }

    if (lockedOverride != null) {
      return lockedOverride!;
    }

    final errorText = state.error?.toString();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Detta innehåll är låst.\nKöp kursen Vit Magi eller bli medlem för att låsa upp.',
            textAlign: TextAlign.center,
          ),
          if (errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              errorText,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => _startCheckout(
              context: context,
              ref: ref,
              authState: authState,
              body: {'type': 'course', 'slug': courseSlug},
              successLabel: 'Kunde inte starta betalning: ',
            ),
            child: const Text('Köp Vit Magi'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _startCheckout(
              context: context,
              ref: ref,
              authState: authState,
              body: const {'type': 'subscription', 'interval': 'month'},
              successLabel: 'Kunde inte öppna checkout: ',
            ),
            child: const Text('Bli medlem'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => notifier.refresh(),
            child: const Text('Uppdatera status'),
          ),
        ],
      ),
    );
  }

  Future<void> _startCheckout({
    required BuildContext context,
    required WidgetRef ref,
    required AuthState authState,
    required Map<String, String> body,
    required String successLabel,
  }) async {
    if (!authState.isAuthenticated) {
      _redirectToLogin(context);
      return;
    }
    try {
      final api = ref.read(checkoutApiProvider);
      final type = body['type'];
      late final String url;
      if (type == 'subscription') {
        url = await api.startMembershipCheckout(
          interval: body['interval'] ?? 'month',
        );
      } else {
        final slug = body['slug'];
        if (slug == null || slug.isEmpty) {
          throw Exception('Course slug saknas');
        }
        url = await api.startCourseCheckout(slug: slug);
      }
      if (!context.mounted) return;
      context.push(RoutePath.checkout, extra: url);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$successLabel$e')));
    }
  }

  void _redirectToLogin(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Logga in för att fortsätta.')),
    );
    final router = GoRouter.of(context);
    String redirect = RoutePath.landing;
    try {
      redirect = GoRouterState.of(context).uri.toString();
    } catch (_) {}
    router.goNamed(AppRoute.login, queryParameters: {'redirect': redirect});
  }
}
