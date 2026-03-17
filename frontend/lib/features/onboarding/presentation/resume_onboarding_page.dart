import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';

class ResumeOnboardingPage extends ConsumerStatefulWidget {
  const ResumeOnboardingPage({super.key});

  @override
  ConsumerState<ResumeOnboardingPage> createState() =>
      _ResumeOnboardingPageState();
}

class _ResumeOnboardingPageState extends ConsumerState<ResumeOnboardingPage> {
  bool _navigated = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    if (!_navigated &&
        !authState.isLoading &&
        authState.profile != null &&
        authState.onboarding != null) {
      _navigated = true;
      final target = authState.onboarding!.nextStep;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !context.mounted) return;
        context.go(target.isEmpty ? RoutePath.home : target);
      });
    }

    return const AppScaffold(
      title: 'Onboarding',
      disableBack: true,
      showHomeAction: false,
      useBasePage: false,
      contentPadding: EdgeInsets.zero,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
