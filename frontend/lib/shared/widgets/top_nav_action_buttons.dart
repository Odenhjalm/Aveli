import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/auth/application/user_access_provider.dart';

class TopNavActionButtons extends ConsumerWidget {
  const TopNavActionButtons({super.key, this.iconColor});

  final Color? iconColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final access = ref.watch(userAccessProvider);
    final profile = authState.profile;
    final color = iconColor ?? Theme.of(context).colorScheme.onSurface;
    final isTeacher = access.isTeacher;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Hem',
          icon: Icon(Icons.home_outlined, color: color),
          onPressed: () => context.goNamed(AppRoute.courseCatalog),
        ),
        if (isTeacher)
          IconButton(
            tooltip: 'Lärarhem',
            icon: Icon(Icons.home_work_outlined, color: color),
            onPressed: () => context.goNamed(AppRoute.teacherHome),
          ),
        if (profile != null)
          IconButton(
            tooltip: 'Profil',
            icon: Icon(Icons.person_outline, color: color),
            onPressed: () => context.goNamed(AppRoute.profile),
          ),
      ],
    );
  }
}
