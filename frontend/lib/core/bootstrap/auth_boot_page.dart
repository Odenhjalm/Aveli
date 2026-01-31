import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/widgets/app_logo.dart';

class AuthBootPage extends ConsumerWidget {
  const AuthBootPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the boot surface stable and avoid triggering any auth-required
    // providers until the profile has been verified.
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final message = auth.isLoading ? 'Verifierar session…' : 'Förbereder…';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 120),
              const SizedBox(height: 18),
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
