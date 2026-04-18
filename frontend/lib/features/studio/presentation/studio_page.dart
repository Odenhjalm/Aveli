import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/hero_background.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/presentation/teacher_home_page.dart';

class StudioPage extends ConsumerWidget {
  const StudioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    if (!authState.canEnterApp) {
      return const AppScaffold(
        title: 'Studio',
        body: Center(child: Text('Backend entry kravs for Studio.')),
      );
    }

    final statusAsync = ref.watch(studioStatusProvider);
    return statusAsync.when(
      loading: () => const AppScaffold(
        title: 'Studio',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AppScaffold(
        title: 'Studio',
        body: Center(child: Text('Fel: $error')),
      ),
      data: (status) {
        if (status.isTeacher) {
          return const TeacherHomeScreen();
        }
        return _StudioApplyView(status: status);
      },
    );
  }
}

class _StudioApplyView extends StatelessWidget {
  const _StudioApplyView({required this.status});

  final StudioStatus status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final message = status.hasApplication
        ? 'Din ansokan ar pausad tills en administrator aktiverar lararrollen.'
        : 'Studio kraver lararroll enligt Baseline V2. Be en administrator aktivera lararrollen.';

    return AppScaffold(
      title: 'Studio',
      extendBodyBehindAppBar: true,
      transparentAppBar: true,
      background: const HeroBackground(
        assetPath: 'images/bakgrund.png',
        opacity: 0.72,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 100, 16, 16),
          child: GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Studio ar pa vag',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
