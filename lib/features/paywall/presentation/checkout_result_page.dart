import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wisdom/core/routing/route_paths.dart';
import 'package:wisdom/features/paywall/application/entitlements_notifier.dart';

class CheckoutResultPage extends ConsumerWidget {
  const CheckoutResultPage({super.key, required this.success});

  final bool success;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future.microtask(() async {
      if (success) {
        await ref.read(entitlementsNotifierProvider.notifier).refresh();
      }
      if (context.mounted) {
        context.go(RoutePath.home);
      }
    });

    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
