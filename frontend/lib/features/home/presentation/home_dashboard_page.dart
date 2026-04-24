import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/auth/application/user_access_provider.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/data/notifications_repository.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/home/application/home_audio_controller.dart';
import 'package:aveli/features/home/presentation/widgets/home_audio_section.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/theme/design_tokens.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/widgets/course_intro_badge.dart';
import 'package:aveli/shared/widgets/courses_showcase_section.dart';
import 'package:aveli/core/bootstrap/auth_boot_page.dart';

class HomeDashboardPage extends ConsumerStatefulWidget {
  const HomeDashboardPage({super.key});

  @override
  ConsumerState<HomeDashboardPage> createState() => _HomeDashboardPageState();
}

class _HomeDashboardPageState extends ConsumerState<HomeDashboardPage> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final access = ref.watch(userAccessProvider);
    final notificationsAsync = ref.watch(notificationsProvider);
    final profile = authState.profile;
    if (profile == null) {
      return const AuthBootPage();
    }

    final isTeacher = access.isTeacher || access.isAdmin;

    return AppScaffold(
      title: '',
      disableBack: true,
      showHomeAction: false,
      logoSize: 0,
      maxContentWidth: 1320,
      contentPadding: EdgeInsets.zero,
      actions: [
        IconButton(
          tooltip: 'Hem',
          onPressed: () => context.goNamed(AppRoute.home),
          icon: const Icon(Icons.home_outlined),
        ),
        if (isTeacher)
          IconButton(
            tooltip: 'Studio',
            onPressed: () => context.goNamed(AppRoute.studio),
            icon: const Icon(Icons.edit),
          ),
        if (access.isAdmin)
          IconButton(
            tooltip: 'Mediekontroll',
            onPressed: () => context.goNamed(AppRoute.adminMedia),
            icon: const Icon(Icons.perm_media_outlined),
          ),
        IconButton(
          tooltip: 'Profil',
          onPressed: () => context.goNamed(AppRoute.profile),
          icon: const Icon(Icons.person),
        ),
      ],
      background: FullBleedBackground(
        // Bundlade bakgrunder laddas lokalt för att slippa 401-svar från API:t.
        image: AppImages.background,
        alignment: Alignment.center,
        topOpacity: 0.22,
        overlayColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF000000).withValues(alpha: 0.3)
            : const Color(0xFFFFE2B8).withValues(alpha: 0.16),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(landing.popularCoursesProvider);
          ref.invalidate(coursesProvider);
          ref.invalidate(homeAudioProvider);
          ref.invalidate(notificationsProvider);
          await ref.read(authControllerProvider.notifier).loadSession();
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            const pagePadding = EdgeInsets.fromLTRB(20, 118, 20, 44);
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: pagePadding,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isWide ? 860 : 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _NotificationsPanel(
                        notificationsAsync: notificationsAsync,
                      ),
                      const SizedBox(height: 18),
                      const HomeAudioSection(),
                      const SizedBox(height: 18),
                      const CoursesShowcaseSection(
                        title: 'Utforska kurser',
                        layout: CoursesShowcaseLayout.vertical,
                        desktop: CoursesShowcaseDesktop(columns: 2, rows: 3),
                        includeOuterChrome: false,
                        showHeroBadge: false,
                        showSeeAll: true,
                        ctaGradient: kBrandBluePurpleGradient,
                        tileScale: 0.85,
                        tileTextColor: DesignTokens.bodyTextColor,
                        introBadgeVariant: CourseIntroBadgeVariant.link,
                        gridCrossAxisSpacing: 2,
                        gridMainAxisSpacing: 2,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationsPanel extends StatelessWidget {
  const _NotificationsPanel({required this.notificationsAsync});

  final AsyncValue<List<NotificationItem>> notificationsAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: notificationsAsync.when(
          loading: () => const SizedBox(
            height: 36,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (error, _) => Text(
            'Kunde inte hämta aviseringar.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          data: (notifications) {
            final latest = notifications.take(5).toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aviseringar',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (latest.isEmpty)
                  Text(
                    'Inga aviseringar ännu.',
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  ...latest.map(
                    (notification) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notification.type,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _payloadSummary(notification.payload),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _payloadSummary(Map<String, dynamic> payload) {
    final title = payload['title']?.toString().trim();
    if (title != null && title.isNotEmpty) return title;
    final lessonId = payload['lesson_id']?.toString();
    final courseId = payload['course_id']?.toString();
    return [
      if (lessonId != null && lessonId.isNotEmpty) 'lesson_id: $lessonId',
      if (courseId != null && courseId.isNotEmpty) 'course_id: $courseId',
    ].join(' | ');
  }
}
