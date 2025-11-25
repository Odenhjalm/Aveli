import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisdom/core/auth/auth_controller.dart';
import 'package:wisdom/core/routing/app_routes.dart';
import 'package:wisdom/shared/widgets/gradient_button.dart';

class ProfileLogoutSection extends ConsumerWidget {
  const ProfileLogoutSection({
    super.key,
    this.alignment = Alignment.centerLeft,
    this.padding = const EdgeInsets.symmetric(vertical: 24),
  });

  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    return Padding(
      padding: padding,
      child: Align(
        alignment: alignment,
        child: GradientButton.icon(
          onPressed: () async {
            final shouldLogout = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Logga ut'),
                content: const Text('Är du säker på att du vill logga ut?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Avbryt'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      foregroundColor: theme.colorScheme.onError,
                      backgroundColor: color,
                    ),
                    child: const Text('Logga ut'),
                  ),
                ],
              ),
            );
            if (shouldLogout != true) return;
            await ref.read(authControllerProvider.notifier).logout();
            if (context.mounted) {
              GoRouter.of(context).goNamed(AppRoute.landing);
            }
          },
          icon: const Icon(Icons.logout_rounded, color: Colors.white),
          label: const Text('Logga ut'),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      ),
    );
  }
}
