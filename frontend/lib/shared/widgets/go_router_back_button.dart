import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisdom/core/routing/app_routes.dart';

/// Back button that works with GoRouter and fallbacks depending on auth state.
class GoRouterBackButton extends ConsumerWidget {
  const GoRouterBackButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () {
        final router = GoRouter.of(context);
        if (router.canPop()) {
          router.pop();
          return;
        }
        context.goNamed(AppRoute.landing);
      },
    );
  }
}
