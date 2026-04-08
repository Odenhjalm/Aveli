import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Admininstallningar',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ingen kanonisk auth/onboarding-installyta finns har.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Adminbootstrap ar operatorstyrd och lararroll styrs via de kanoniska grant/revoke-rutterna. Statistik-, certifikat- och prioriteringsytor ingar inte i Auth + Onboarding-kontraktet.',
                  ),
                  const SizedBox(height: 20),
                  GradientButton(
                    onPressed: () => context.goNamed(AppRoute.admin),
                    child: const Text('Tillbaka till admin'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
