import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/paywall/application/entitlements_notifier.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';

class CheckoutResultPage extends ConsumerStatefulWidget {
  const CheckoutResultPage({
    super.key,
    required this.success,
    this.sessionId,
    this.errored = false,
  });

  final bool success;
  final String? sessionId;
  final bool errored;

  @override
  ConsumerState<CheckoutResultPage> createState() => _CheckoutResultPageState();
}

class _CheckoutResultPageState extends ConsumerState<CheckoutResultPage> {
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_handleResult);
  }

  Future<void> _handleResult() async {
    if (_handled) return;
    _handled = true;

    if (widget.success && !widget.errored) {
      final sessionId = widget.sessionId;
      if (sessionId != null && sessionId.isNotEmpty) {
        final checkoutApi = ref.read(checkoutApiProvider);
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (DateTime.now().isBefore(deadline)) {
          try {
            final status = await checkoutApi.fetchSessionStatus(sessionId);
            final membershipStatus =
                status['membership_status']?.toString().toLowerCase() ?? '';
            if (membershipStatus == 'active' ||
                membershipStatus == 'trialing') {
              break;
            }
            final pollAfterMs =
                int.tryParse(status['poll_after_ms']?.toString() ?? '') ?? 2000;
            await Future<void>.delayed(
              Duration(milliseconds: pollAfterMs.clamp(500, 5000)),
            );
          } catch (_) {
            break;
          }
        }
      }
      await ref.read(entitlementsNotifierProvider.notifier).refresh();
    }

    await ref.read(authControllerProvider.notifier).refreshOnboarding();
    if (!mounted || !context.mounted) return;
    context.go(RoutePath.resumeOnboarding);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.success ? 'Bekräftar medlemskap' : 'Avbryter checkout';
    return AppScaffold(
      title: title,
      disableBack: true,
      showHomeAction: false,
      useBasePage: false,
      contentPadding: EdgeInsets.zero,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              widget.success
                  ? 'Synkar betalning...'
                  : 'Återgår till onboarding...',
            ),
          ],
        ),
      ),
    );
  }
}
