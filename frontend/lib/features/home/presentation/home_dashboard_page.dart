import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_extras.dart';
import 'package:aveli/features/auth/application/user_access_provider.dart';
import 'package:aveli/data/models/activity.dart';
import 'package:aveli/data/models/service.dart';
import 'package:aveli/features/home/application/home_providers.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/theme/design_tokens.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/widgets/course_intro_badge.dart';
import 'package:aveli/shared/widgets/courses_showcase_section.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/shared/widgets/effects_backdrop_filter.dart';
import 'package:aveli/shared/widgets/semantic_text.dart';
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
    final profile = authState.profile;
    if (profile == null) {
      return const AuthBootPage();
    }

    final isTeacher = access.isTeacher || access.isAdmin;
    final feedAsync = ref.watch(homeFeedProvider);
    final servicesAsync = ref.watch(homeServicesProvider);

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
          ref.invalidate(homeFeedProvider);
          ref.invalidate(homeServicesProvider);
          ref.invalidate(landing.popularCoursesProvider);
          ref.invalidate(coursesProvider);
          await ref.read(authControllerProvider.notifier).loadSession();
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            const pagePadding = EdgeInsets.fromLTRB(20, 118, 20, 44);
            if (isWide) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: pagePadding,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Transform.translate(
                                  offset: const Offset(-12, -10),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 860,
                                    ),
                                    child: const CoursesShowcaseSection(
                                      title: 'Utforska kurser',
                                      layout: CoursesShowcaseLayout.vertical,
                                      desktop: CoursesShowcaseDesktop(
                                        columns: 2,
                                        rows: 3,
                                      ),
                                      includeOuterChrome: false,
                                      showHeroBadge: false,
                                      showSeeAll: true,
                                      ctaGradient: kBrandBluePurpleGradient,
                                      tileScale: 0.85,
                                      tileTextColor: DesignTokens.bodyTextColor,
                                      introBadgeVariant:
                                          CourseIntroBadgeVariant.link,
                                      gridCrossAxisSpacing: 2,
                                      gridMainAxisSpacing: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Padding(
                              padding: const EdgeInsets.only(top: 90),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 360,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _FeedSection(feedAsync: feedAsync),
                                    const SizedBox(height: 24),
                                    _ServicesSection(
                                      servicesAsync: servicesAsync,
                                      isAuthenticated:
                                          authState.isAuthenticated,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: pagePadding,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        introBadgeVariant: CourseIntroBadgeVariant.link,
                        gridCrossAxisSpacing: 2,
                        gridMainAxisSpacing: 2,
                      ),
                      const SizedBox(height: 22),
                      _FeedSection(feedAsync: feedAsync),
                      const SizedBox(height: 22),
                      _ServicesSection(
                        servicesAsync: servicesAsync,
                        isAuthenticated: authState.isAuthenticated,
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

class _FeedSection extends StatelessWidget {
  const _FeedSection({required this.feedAsync});

  final AsyncValue<List<Activity>> feedAsync;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Gemensam vagg',
      trailing: TextButton(
        onPressed: () => context.goNamed(AppRoute.community),
        child: const Text('Visa allt'),
      ),
      child: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text('Kunde inte hamta feed: ${error.toString()}'),
        data: (activities) {
          if (activities.isEmpty) {
            return const MetaText('Inga aktiviteter annu.');
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final activity in activities.take(10))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: _GlassTile(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.bolt_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              NameText(
                                activity.summary.isEmpty
                                    ? activity.type
                                    : activity.summary,
                                baseStyle: Theme.of(
                                  context,
                                ).textTheme.titleMedium,
                                fontWeight: FontWeight.w600,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              MetaText(
                                MaterialLocalizations.of(
                                  context,
                                ).formatFullDate(activity.occurredAt.toLocal()),
                                baseStyle: Theme.of(
                                  context,
                                ).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ServicesSection extends StatelessWidget {
  const _ServicesSection({
    required this.servicesAsync,
    required this.isAuthenticated,
  });

  final AsyncValue<List<Service>> servicesAsync;
  final bool isAuthenticated;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Tjanster',
      trailing: TextButton(
        onPressed: () => context.goNamed(
          AppRoute.community,
          queryParameters: const {'tab': 'services'},
          extra: const CommunityRouteArgs(initialTab: 'services'),
        ),
        child: const Text('Visa alla'),
      ),
      child: servicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text(
          'Kunde inte hamta tjanster: ${AppFailure.from(error).message}',
        ),
        data: (services) {
          if (services.isEmpty) {
            return const MetaText('Inga tjanster publicerade just nu.');
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: services
                .take(5)
                .map((service) {
                  final gate = _resolveGate(service);
                  final action = gate.action == _GateAction.login
                      ? () => _goToLogin(context, service)
                      : null;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _GlassTile(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          NameText(
                            service.title,
                            baseStyle: Theme.of(context).textTheme.titleMedium,
                            fontWeight: FontWeight.w600,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (service.description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            MetaText(
                              service.description,
                              baseStyle: Theme.of(context).textTheme.bodyMedium,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (service.requiresCertification) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Certifieringsbaserade bokningar ar pausade i Baseline V2.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${service.price.toStringAsFixed(2)} ${service.currency.toUpperCase()}',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              if (action != null)
                                GradientButton(
                                  onPressed: action,
                                  child: Text(gate.label),
                                ),
                            ],
                          ),
                          if (gate.helper != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              gate.helper!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          );
        },
      ),
    );
  }

  ({_GateAction? action, String label, String? helper}) _resolveGate(
    Service service,
  ) {
    if (!service.requiresCertification) {
      return (
        action: null,
        label: 'Boka',
        helper: 'Bokning ar inte tillganglig i appen just nu.',
      );
    }
    if (!isAuthenticated) {
      return (
        action: _GateAction.login,
        label: 'Logga in',
        helper: 'Logga in for att visa tjansten.',
      );
    }
    return (
      action: null,
      label: 'Inte tillgangligt',
      helper: 'Certifieringsbaserade bokningar ar pausade i Baseline V2.',
    );
  }

  void _goToLogin(BuildContext context, Service service) {
    final router = GoRouter.of(context);
    var redirect = '/';
    try {
      redirect = router.namedLocation(
        AppRoute.serviceDetail,
        pathParameters: {'id': service.id},
      );
    } catch (_) {}
    router.goNamed(AppRoute.login, queryParameters: {'redirect': redirect});
  }
}

enum _GateAction { login }

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _GlassSection(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SectionHeading(
                title,
                baseStyle: Theme.of(context).textTheme.titleLarge,
                fontWeight: FontWeight.bold,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _GlassSection extends StatelessWidget {
  const _GlassSection({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.38);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: EffectsBackdropFilter(
        sigmaX: 20,
        sigmaY: 20,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [baseColor, baseColor.withValues(alpha: 0.68)],
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _GlassTile extends StatelessWidget {
  const _GlassTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: EffectsBackdropFilter(
        sigmaX: 16,
        sigmaY: 16,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            color: Colors.white.withValues(alpha: 0.22),
          ),
          child: child,
        ),
      ),
    );
  }
}
