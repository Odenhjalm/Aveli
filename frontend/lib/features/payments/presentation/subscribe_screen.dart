import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class SubscribeScreen extends ConsumerStatefulWidget {
  const SubscribeScreen({super.key});

  @override
  ConsumerState<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends ConsumerState<SubscribeScreen> {
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
    final envBlocked = envInfo.hasIssues;

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
                      Card(
                        elevation: 0,
                        color: Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: 0.08),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Prenumerationsstatus visas inte längre i appen.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.secondary,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    gap16,
                    Text(
                      'Bli medlem',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    gap12,
                    const Text(
                      'Nya medlemsköp är inte tillgängliga i appen just nu.',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'För betalningsärenden använder du kundportalen när den är tillgänglig.',
                      style: Theme.of(context).textTheme.bodyMedium,
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

  void _redirectToLogin() {
    if (!mounted) return;
    final redirect = GoRouter.of(context).namedLocation(AppRoute.subscribe);
    context.goNamed(AppRoute.login, queryParameters: {'redirect': redirect});
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
