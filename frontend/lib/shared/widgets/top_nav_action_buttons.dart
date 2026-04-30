import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/models/text_bundle.dart';
import 'package:aveli/features/auth/application/user_access_provider.dart';
import 'package:aveli/shared/data/app_render_inputs_repository.dart';

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
    final renderInputs = ref.watch(appRenderInputsProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavigationIconButton(
          textId: 'global_system.navigation.home',
          icon: Icons.home_outlined,
          color: color,
          renderInputs: renderInputs,
          onPressed: () => context.goNamed(AppRoute.courseCatalog),
        ),
        if (isTeacher)
          _NavigationIconButton(
            textId: 'global_system.navigation.teacher_home',
            icon: Icons.home_work_outlined,
            color: color,
            renderInputs: renderInputs,
            onPressed: () => context.goNamed(AppRoute.teacherHome),
          ),
        if (profile != null)
          _NavigationIconButton(
            textId: 'global_system.navigation.profile',
            icon: Icons.person_outline,
            color: color,
            renderInputs: renderInputs,
            onPressed: () => context.goNamed(AppRoute.profile),
          ),
      ],
    );
  }
}

class _NavigationIconButton extends StatelessWidget {
  const _NavigationIconButton({
    required this.textId,
    required this.icon,
    required this.color,
    required this.renderInputs,
    required this.onPressed,
  });

  final String textId;
  final IconData icon;
  final Color color;
  final AsyncValue<AppRenderInputs> renderInputs;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = renderInputs.hasValue
        ? resolveNavigationText(textId, renderInputs.requireValue.textBundles)
        : null;
    return IconButton(
      tooltip: label,
      icon: Icon(icon, color: color),
      onPressed: label == null ? null : onPressed,
    );
  }
}

String? resolveNavigationText(String textId, List<TextBundle> textBundles) {
  try {
    return resolveText(textId, textBundles);
  } on StateError {
    return null;
  }
}
