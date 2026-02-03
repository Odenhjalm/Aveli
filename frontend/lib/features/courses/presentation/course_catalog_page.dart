import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:aveli/core/bootstrap/safe_media.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import 'package:aveli/shared/utils/course_cover_assets.dart';
import 'package:aveli/shared/utils/course_journey_step.dart';
import 'package:aveli/shared/theme/design_tokens.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/top_nav_action_buttons.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/card_text.dart';
import 'package:aveli/shared/widgets/semantic_text.dart';

class CourseCatalogPage extends ConsumerWidget {
  const CourseCatalogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final assets = ref.watch(backendAssetResolverProvider);
    final coursesAsync = ref.watch(coursesProvider);

    final courses = coursesAsync.valueOrNull ?? const <CourseSummary>[];
    final introCourses = <CourseSummary>[];
    final step1Courses = <CourseSummary>[];
    final step2Courses = <CourseSummary>[];
    final step3Courses = <CourseSummary>[];
    final unclassified = <CourseSummary>[];

    for (final course in courses) {
      switch (course.journeyStep) {
        case CourseJourneyStep.intro:
          introCourses.add(course);
          break;
        case CourseJourneyStep.step1:
          step1Courses.add(course);
          break;
        case CourseJourneyStep.step2:
          step2Courses.add(course);
          break;
        case CourseJourneyStep.step3:
          step3Courses.add(course);
          break;
        case null:
          unclassified.add(course);
          break;
      }
    }

    if (unclassified.isNotEmpty) {
      assert(() {
        debugPrint(
          'Alla kurser: hoppar över ${unclassified.length} publicerade kurser utan giltig journey_step.',
        );
        for (final course in unclassified) {
          debugPrint(' - ${course.id} (${course.slug ?? 'saknar slug'})');
        }
        return true;
      }());
    }

    final step3CourseIds = <String>{};
    for (final course in step3Courses) {
      step3CourseIds.add(course.id);
    }

    final step3ProgressAsync = step3CourseIds.isEmpty
        ? const AsyncData(<String, double>{})
        : ref.watch(
            courseProgressProvider(
              CourseProgressRequest(step3CourseIds.toList()),
            ),
          );
    final hasCompletedStep3 =
        step3ProgressAsync.valueOrNull?.values.any((p) => p >= 0.999) == true;
    const proEligibilityHint =
        'Tillgängligt när du har slutfört ett tredje steg';

    final isLoading = coursesAsync.isLoading;
    final Object? error = coursesAsync.error;

    final hasAnyCourses =
        introCourses.isNotEmpty ||
        step1Courses.isNotEmpty ||
        step2Courses.isNotEmpty ||
        step3Courses.isNotEmpty;

    final content = isLoading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? _ErrorState(error: error)
        : !hasAnyCourses
        ? _EmptyState(theme: theme)
        : _CourseJourney(
            introCourses: introCourses,
            step1Courses: step1Courses,
            step2Courses: step2Courses,
            step3Courses: step3Courses,
            assets: assets,
            canApplyForPro: hasCompletedStep3,
            proEligibilityHint: proEligibilityHint,
          );

    return AppScaffold(
      title: 'Alla kurser',
      showHomeAction: false,
      actions: const [TopNavActionButtons()],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          child: content,
        ),
      ),
    );
  }
}

class _CourseJourney extends StatelessWidget {
  const _CourseJourney({
    required this.introCourses,
    required this.step1Courses,
    required this.step2Courses,
    required this.step3Courses,
    required this.assets,
    required this.canApplyForPro,
    required this.proEligibilityHint,
  });

  final List<CourseSummary> introCourses;
  final List<CourseSummary> step1Courses;
  final List<CourseSummary> step2Courses;
  final List<CourseSummary> step3Courses;
  final BackendAssetResolver assets;
  final bool canApplyForPro;
  final String proEligibilityHint;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _SectionHeader(
          title: 'Börja här',
          subtitle: 'Känn efter i din egen takt',
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: _IntroWindow(courses: introCourses, assets: assets),
            ),
          ),
        const SizedBox(height: 34),
        const _SectionHeader(title: 'Din resa'),
        const SizedBox(height: 10),
        _StepsCarousel(
          step1Courses: step1Courses,
          step2Courses: step2Courses,
          step3Courses: step3Courses,
          assets: assets,
        ),
        const SizedBox(height: 34),
        _AveliProSeal(
          canApply: canApplyForPro,
          eligibilityHint: proEligibilityHint,
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(title, baseStyle: t.headlineSmall),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          MetaText(subtitle!, baseStyle: t.bodyLarge),
        ],
      ],
    );
  }
}

class _IntroWindow extends StatelessWidget {
  const _IntroWindow({required this.courses, required this.assets});

  final List<CourseSummary> courses;
  final BackendAssetResolver assets;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return const GlassCard(
        opacity: 0.10,
        sigmaX: 10,
        sigmaY: 10,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: MetaText('Inga introduktionskurser ännu.'),
        ),
      );
    }

    return GlassCard(
      opacity: 0.10,
      sigmaX: 10,
      sigmaY: 10,
      borderColor: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(22),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const cardsPerView = 3;
          const spacing = 12.0;
          final available =
              (constraints.maxWidth - spacing * (cardsPerView - 1)).clamp(
                0.0,
                constraints.maxWidth,
              );
          final cardWidth = available / cardsPerView;
          const aspect = 0.92;
          final cardHeight = cardWidth / aspect;

          return SizedBox(
            height: cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: courses.length,
              separatorBuilder: (_, __) => const SizedBox(width: spacing),
              itemBuilder: (context, index) => SizedBox(
                width: cardWidth,
                child: _IntroCourseCard(course: courses[index], assets: assets),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _IntroCourseCard extends StatelessWidget {
  const _IntroCourseCard({required this.course, required this.assets});

  final CourseSummary course;
  final BackendAssetResolver assets;

  @override
  Widget build(BuildContext context) {
    final title = course.title.trim();
    final slug = (course.slug ?? '').trim();
    final coverUrl = course.coverUrl?.trim();

    final coverProvider = CourseCoverAssets.resolve(
      assets: assets,
      slug: slug,
      coverUrl: coverUrl,
    );
    final isFallbackLogo = coverProvider == null;
    final imageProvider = coverProvider ?? AppImages.logo;

    final radius = BorderRadius.circular(18);

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: slug.isEmpty
            ? null
            : () => context.pushNamed(
                AppRoute.course,
                pathParameters: {'slug': slug},
              ),
        borderRadius: radius,
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          opacity: 0.18,
          sigmaX: 10,
          sigmaY: 10,
          borderRadius: radius,
          borderColor: Colors.white.withValues(alpha: 0.16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _CourseCover(
                imageProvider: imageProvider,
                isFallbackLogo: isFallbackLogo,
              ),
              const SizedBox(height: 10),
              Text(
                title.isNotEmpty ? title : 'Introduktion',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    (Theme.of(context).textTheme.titleSmall ??
                            const TextStyle())
                        .copyWith(
                          color: DesignTokens.bodyTextColor,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
              ),
              const Spacer(),
              const _Chip(icon: Icons.auto_awesome, label: 'Introduktion'),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepsCarousel extends StatelessWidget {
  const _StepsCarousel({
    required this.step1Courses,
    required this.step2Courses,
    required this.step3Courses,
    required this.assets,
  });

  final List<CourseSummary> step1Courses;
  final List<CourseSummary> step2Courses;
  final List<CourseSummary> step3Courses;
  final BackendAssetResolver assets;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final stepWidth = width >= 1200 ? 360.0 : (width >= 900 ? 340.0 : 312.0);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepColumn(
            width: stepWidth,
            stepLabel: 'Steg 1',
            description: 'Fördjupning och grund',
            courses: step1Courses,
            assets: assets,
          ),
          const _StepArrow(),
          _StepColumn(
            width: stepWidth,
            stepLabel: 'Steg 2',
            description: 'Integration och praktik',
            courses: step2Courses,
            assets: assets,
          ),
          const _StepArrow(),
          _StepColumn(
            width: stepWidth,
            stepLabel: 'Steg 3',
            description: 'Fördjupad förståelse och mognad',
            courses: step3Courses,
            assets: assets,
          ),
        ],
      ),
    );
  }
}

class _StepArrow extends StatelessWidget {
  const _StepArrow();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.35);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 56, 10, 0),
      child: Icon(Icons.arrow_forward_rounded, color: color, size: 22),
    );
  }
}

class _StepColumn extends StatelessWidget {
  const _StepColumn({
    required this.width,
    required this.stepLabel,
    required this.description,
    required this.courses,
    required this.assets,
  });

  final double width;
  final String stepLabel;
  final String description;
  final List<CourseSummary> courses;
  final BackendAssetResolver assets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;

    return SizedBox(
      width: width,
      child: GlassCard(
        opacity: 0.12,
        sigmaX: 10,
        sigmaY: 10,
        borderColor: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(22),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stepLabel,
              style: (t.labelLarge ?? const TextStyle()).copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            MetaText(description, baseStyle: t.bodyMedium),
            const SizedBox(height: 14),
            if (courses.isEmpty)
              const MetaText('Inga kurser ännu.')
            else
              Column(
                children: [
                  for (final course in courses) ...[
                    _JourneyCourseCard(
                      course: course,
                      showPrice: true,
                      assets: assets,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _JourneyCourseCard extends StatelessWidget {
  const _JourneyCourseCard({
    required this.course,
    required this.showPrice,
    required this.assets,
    this.badgeText,
  });

  final CourseSummary course;
  final bool showPrice;
  final BackendAssetResolver assets;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final title = course.title.trim();
    final description = course.description?.trim() ?? '';
    final slug = (course.slug ?? '').trim();

    final priceCents = course.priceCents;
    final currency = course.currency;
    final priceLabel = showPrice
        ? _formatPrice(priceCents, currency: currency)
        : null;

    final coverUrl = course.coverUrl?.trim();
    final coverProvider = CourseCoverAssets.resolve(
      assets: assets,
      slug: slug,
      coverUrl: coverUrl,
    );
    final isFallbackLogo = coverProvider == null;
    final imageProvider = coverProvider ?? AppImages.logo;

    final radius = BorderRadius.circular(20);

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: slug.isEmpty
            ? null
            : () => context.pushNamed(
                AppRoute.course,
                pathParameters: {'slug': slug},
              ),
        borderRadius: radius,
        child: GlassCard(
          padding: const EdgeInsets.all(16),
          opacity: 0.18,
          sigmaX: 10,
          sigmaY: 10,
          borderRadius: radius,
          borderColor: Colors.white.withValues(alpha: 0.16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _CourseCover(
                imageProvider: imageProvider,
                isFallbackLogo: isFallbackLogo,
              ),
              const SizedBox(height: 12),
              Text(
                title.isNotEmpty ? title : 'Kurs',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: (t.titleMedium ?? const TextStyle()).copyWith(
                  color: DesignTokens.bodyTextColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                CourseDescriptionText(
                  description,
                  baseStyle: t.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.start,
                children: [
                  if (badgeText != null && badgeText!.trim().isNotEmpty)
                    _Chip(icon: Icons.lock_open_rounded, label: badgeText!),
                  if (priceLabel != null)
                    _Chip(icon: Icons.payments_outlined, label: priceLabel),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _formatPrice(int? cents, {required String currency}) {
    final amountCents = cents ?? 0;
    if (amountCents <= 0) return 'Gratis';
    if (currency != 'sek') {
      final symbol = currency.toUpperCase();
      final value = (amountCents / 100).toStringAsFixed(0);
      return '$value $symbol';
    }
    final amount = (amountCents / 100).round();
    return NumberFormat.currency(
      locale: 'sv_SE',
      symbol: 'kr',
      decimalDigits: 0,
    ).format(amount);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = DesignTokens.bodyTextColor.withValues(alpha: 0.88);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseCover extends StatelessWidget {
  const _CourseCover({
    required this.imageProvider,
    required this.isFallbackLogo,
  });

  final ImageProvider<Object> imageProvider;
  final bool isFallbackLogo;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Padding(
            padding: EdgeInsets.all(isFallbackLogo ? 18 : 0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (SafeMedia.enabled) {
                  SafeMedia.markThumbnails();
                }
                final cacheWidth = SafeMedia.cacheDimension(
                  context,
                  constraints.maxWidth,
                  max: 1200,
                );
                final cacheHeight = SafeMedia.cacheDimension(
                  context,
                  constraints.maxHeight,
                  max: 900,
                );

                Widget fallbackLogo() => Container(
                  color: Colors.white.withValues(alpha: 0.32),
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Image(
                      image: SafeMedia.resizedProvider(
                        AppImages.logo,
                        cacheWidth: cacheWidth,
                        cacheHeight: cacheHeight,
                      ),
                      fit: BoxFit.contain,
                      filterQuality: SafeMedia.filterQuality(
                        full: FilterQuality.high,
                      ),
                      gaplessPlayback: true,
                    ),
                  ),
                );

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    fallbackLogo(),
                    Image(
                      image: SafeMedia.resizedProvider(
                        imageProvider,
                        cacheWidth: cacheWidth,
                        cacheHeight: cacheHeight,
                      ),
                      fit: isFallbackLogo ? BoxFit.contain : BoxFit.cover,
                      filterQuality: SafeMedia.filterQuality(
                        full: FilterQuality.high,
                      ),
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AveliProSeal extends StatefulWidget {
  const _AveliProSeal({required this.canApply, required this.eligibilityHint});

  final bool canApply;
  final String eligibilityHint;

  @override
  State<_AveliProSeal> createState() => _AveliProSealState();
}

class _AveliProSealState extends State<_AveliProSeal> {
  bool _showReadyMessage = false;

  @override
  void didUpdateWidget(covariant _AveliProSeal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.canApply) {
      _showReadyMessage = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const body =
        'För vissa stannar resan vid personlig fördjupning.\n'
        'För andra växer en vilja att dela, guida och stötta.\n\n'
        'När du har gått färdigt ett tredje steg i en kurs\n'
        'kan du ansöka om att bli Aveli-Pro\n'
        'och börja dela den kunskap du kultiverat – på dina villkor.';

    const readyMessage =
        'Ansökan öppnar snart.\nNär den är redo kan du ansöka direkt här.';

    final button = ElevatedButton(
      onPressed: widget.canApply
          ? () => setState(() => _showReadyMessage = true)
          : null,
      child: const Text('Ansök om Aveli-Pro'),
    );

    return GlassCard(
      opacity: 0.10,
      sigmaX: 10,
      sigmaY: 10,
      borderColor: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(26),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: Opacity(
              opacity: 0.22,
              child: Image(
                image: AppImages.logo,
                width: 48,
                height: 48,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                'När du är redo att bära det vidare',
                baseStyle: t.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: (t.bodyLarge ?? t.bodyMedium ?? const TextStyle())
                    .copyWith(height: 1.4),
              ),
              const SizedBox(height: 18),
              if (widget.canApply)
                button
              else
                Tooltip(message: widget.eligibilityHint, child: button),
              if (!widget.canApply) ...[
                const SizedBox(height: 10),
                MetaText(widget.eligibilityHint, baseStyle: t.bodyMedium),
              ],
              if (widget.canApply && _showReadyMessage) ...[
                const SizedBox(height: 12),
                MetaText(readyMessage, baseStyle: t.bodyMedium),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 56,
            color: theme.colorScheme.onSurface,
          ),
          const SizedBox(height: 12),
          Text(
            'Inga publicerade kurser ännu.',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Kom tillbaka snart.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            'Kunde inte hämta kurser just nu.',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (error != null)
            Text(
              error.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}
