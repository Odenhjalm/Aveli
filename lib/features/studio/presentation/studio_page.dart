import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisdom/core/auth/auth_controller.dart';
import 'package:wisdom/core/routing/app_routes.dart';
import 'package:wisdom/shared/widgets/app_scaffold.dart';
import 'package:wisdom/shared/widgets/glass_card.dart';
import 'package:wisdom/shared/widgets/hero_background.dart';
import 'package:wisdom/features/studio/application/studio_providers.dart';
import 'package:wisdom/features/studio/data/studio_repository.dart';
import 'package:wisdom/features/studio/presentation/teacher_home_page.dart';

class StudioPage extends ConsumerWidget {
  const StudioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final profile = authState.profile;
    if (profile == null) {
      return const AppScaffold(
        title: 'Studio',
        body: Center(child: Text('Logga in för att fortsätta.')),
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
        final isTeacher =
            status.isTeacher || profile.isTeacher || profile.isAdmin;
        if (isTeacher) {
          return const TeacherHomeScreen();
        }
        return _StudioApplyView(status: status);
      },
    );
  }
}

class _StudioApplyView extends ConsumerStatefulWidget {
  const _StudioApplyView({required this.status});

  final StudioStatus status;

  @override
  ConsumerState<_StudioApplyView> createState() => _StudioApplyViewState();
}

class _StudioApplyViewState extends ConsumerState<_StudioApplyView> {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final verified = widget.status.verifiedCertificates;
    final message = verified > 0
        ? 'Dina verifierade certifikat aktiverar Pro-status när sista kursdel är klar. Studio låses automatiskt upp därefter.'
        : 'Du behöver minst ett verifierat certifikat för att få tillgång till Studio. Lägg till certifikat på din profil och invänta verifiering.';

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
                  'Studio är på väg',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(message),
                const SizedBox(height: 16),
                Text('Verifierade certifikat: $verified'),
                if (verified == 0) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.pushNamed(AppRoute.profile),
                    child: const Text(
                      'Gå till profil för att lägga till certifikat',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
