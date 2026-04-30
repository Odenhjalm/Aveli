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
import 'package:aveli/features/home/application/home_entry_view_provider.dart';
import 'package:aveli/features/home/data/home_entry_view_repository.dart';
import 'package:aveli/features/home/presentation/widgets/home_audio_section.dart';
import 'package:aveli/features/home/widgets/ongoing_courses_strip.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/theme/design_tokens.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
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
    final notificationsReadModel = notificationsAsync.valueOrNull;

    return AppScaffold(
      title: '',
      disableBack: true,
      showHomeAction: false,
      logoSize: 0,
      maxContentWidth: 1320,
      contentPadding: EdgeInsets.zero,
      actions: [
        if (notificationsReadModel?.showNotificationsBar == true)
          _NotificationsHeaderStrip(
            notifications: notificationsReadModel!.notifications,
          ),
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
          ref.invalidate(homeEntryViewProvider);
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: isWide ? 860 : 720),
                      child: const HomeAudioSection(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _HomeCoursesShowcaseArea(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeCoursesShowcaseArea extends ConsumerWidget {
  const _HomeCoursesShowcaseArea();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses =
        ref.watch(homeEntryViewProvider).valueOrNull ??
        const <HomeEntryOngoingCourse>[];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
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
                    gridCrossAxisSpacing: 2,
                    gridMainAxisSpacing: 2,
                  ),
                  Positioned(
                    top: 24,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: OngoingCoursesStrip(
                          key: const ValueKey('home-ongoing-courses-strip'),
                          courses: courses,
                          onOpenLesson: (lessonId) => context.pushNamed(
                            AppRoute.lesson,
                            pathParameters: {'id': lessonId},
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsHeaderStrip extends StatelessWidget {
  const _NotificationsHeaderStrip({required this.notifications});

  final List<NotificationHeaderItem> notifications;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      key: const ValueKey('notifications-header-strip'),
      constraints: const BoxConstraints(maxWidth: 520),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.16),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: notifications
                .map(
                  (notification) =>
                      _NotificationHeaderItemView(notification: notification),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

class _NotificationHeaderItemView extends StatelessWidget {
  const _NotificationHeaderItemView({required this.notification});

  final NotificationHeaderItem notification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.notifications_none_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              notification.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (notification.subtitle != null) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                notification.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
            ),
          ],
          if (notification.ctaLabel != null && notification.ctaUrl != null) ...[
            const SizedBox(width: 8),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => context.go(notification.ctaUrl!),
              child: Text(
                notification.ctaLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
