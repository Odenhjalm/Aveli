import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/bootstrap/safe_media.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/shared/theme/design_tokens.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import 'package:aveli/shared/utils/course_cover_assets.dart';
import 'package:aveli/shared/utils/money.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/top_nav_action_buttons.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/card_text.dart';
import 'package:aveli/shared/widgets/course_intro_badge.dart';
import 'package:aveli/shared/widgets/semantic_text.dart';
import 'package:aveli/shared/utils/course_journey_step.dart';

class CourseCatalogPage extends ConsumerWidget {
  const CourseCatalogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(coursesProvider);
    final assets = ref.watch(backendAssetResolverProvider);
    final mediaRepository = ref.watch(mediaRepositoryProvider);

    return AppScaffold(
      title: 'Alla kurser',
      showHomeAction: false,
      logoSize: 0,
      maxContentWidth: 1200,
      actions: const [TopNavActionButtons()],
      body: SafeArea(
        child: coursesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorState(error: error),
          data: (courses) => _JourneyPage(
            courses: courses,
            assets: assets,
            mediaRepository: mediaRepository,
          ),
        ),
      ),
    );
  }
}

class _JourneyPage extends ConsumerWidget {
  const _JourneyPage({
    required this.courses,
    required this.assets,
    required this.mediaRepository,
  });

  final List<CourseSummary> courses;
  final BackendAssetResolver assets;
  final MediaRepository mediaRepository;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final published = courses
        .where((course) => (course.slug ?? '').trim().isNotEmpty)
        .toList(growable: false);

    if (published.isEmpty) {
      final theme = Theme.of(context);
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
              'Kom tillbaka snart så fyller vi på med mer.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final introCourses = <CourseSummary>[];
    final step1Courses = <CourseSummary>[];
    final step2Courses = <CourseSummary>[];
    final step3Courses = <CourseSummary>[];
    final unclassified = <CourseSummary>[];

    for (final course in published) {
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
        default:
          unclassified.add(course);
          break;
      }
    }

    assert(() {
      if (unclassified.isEmpty) return true;
      debugPrint(
        'CourseCatalogPage: ${unclassified.length} course(s) missing/invalid journey_step, omitted from rendering: '
        '${unclassified.map((c) => c.id).join(', ')}',
      );
      return true;
    }());

    final step3Ids = step3Courses
        .map((course) => course.id)
        .toList(growable: false);

    final step3ProgressAsync = ref.watch(
      courseProgressProvider(CourseProgressRequest(step3Ids)),
    );
    final hasCompletedStep3 =
        step3ProgressAsync.valueOrNull?.values.any((value) => value >= 0.999) ??
        false;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActIntroSection(
            courses: introCourses,
            assets: assets,
            mediaRepository: mediaRepository,
          ),
          const SizedBox(height: 22),
          _ActJourneySection(
            step1: List.unmodifiable(step1Courses),
            step2: List.unmodifiable(step2Courses),
            step3: List.unmodifiable(step3Courses),
            assets: assets,
            mediaRepository: mediaRepository,
          ),
          const SizedBox(height: 26),
          _ActAveliProSection(isEnabled: hasCompletedStep3),
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

class _ActIntroSection extends StatelessWidget {
  const _ActIntroSection({
    required this.courses,
    required this.assets,
    required this.mediaRepository,
  });

  final List<CourseSummary> courses;
  final BackendAssetResolver assets;
  final MediaRepository mediaRepository;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 22),
          opacity: 0.1,
          sigmaX: 10,
          sigmaY: 10,
          borderColor: Colors.white.withValues(alpha: 0.16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                'Börja här',
                baseStyle: theme.textTheme.titleLarge,
                fontWeight: FontWeight.w800,
              ),
              const SizedBox(height: 4),
              MetaText(
                'Känn efter i din egen takt',
                baseStyle: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 10.0;
                  final width = constraints.maxWidth;
                  final tileWidth = (width - (spacing * 2)) / 3;

                  final imageHeight = tileWidth * 9 / 16;
                  const reservedBottom = 92.0;
                  final listHeight = (imageHeight + reservedBottom)
                      .clamp(156.0, 220.0)
                      .toDouble();

                  return SizedBox(
                    height: listHeight,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: courses.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: spacing),
                      itemBuilder: (context, index) => SizedBox(
                        width: tileWidth,
                        child: _IntroMiniCourseCard(
                          course: courses[index],
                          assets: assets,
                          mediaRepository: mediaRepository,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActJourneySection extends StatelessWidget {
  const _ActJourneySection({
    required this.step1,
    required this.step2,
    required this.step3,
    required this.assets,
    required this.mediaRepository,
  });

  final List<CourseSummary> step1;
  final List<CourseSummary> step2;
  final List<CourseSummary> step3;
  final BackendAssetResolver assets;
  final MediaRepository mediaRepository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Din resa',
          baseStyle: theme.textTheme.headlineSmall,
          fontWeight: FontWeight.w800,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 980;
            final arrowColor = theme.colorScheme.onSurface.withValues(
              alpha: 0.55,
            );

            const minColumnWidth = 320.0;
            final available = constraints.maxWidth;
            final columnWidth = isWide ? (available - 96) / 3 : minColumnWidth;

            Widget arrow() => Padding(
              padding: const EdgeInsets.only(top: 42),
              child: Icon(Icons.arrow_forward_rounded, color: arrowColor),
            );

            final row = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: columnWidth,
                  child: _JourneyStepColumn(
                    label: 'Steg 1',
                    description: 'Fördjupning och grund',
                    courses: step1,
                    assets: assets,
                    mediaRepository: mediaRepository,
                  ),
                ),
                const SizedBox(width: 12),
                arrow(),
                const SizedBox(width: 12),
                SizedBox(
                  width: columnWidth,
                  child: _JourneyStepColumn(
                    label: 'Steg 2',
                    description: 'Integration och praktik',
                    courses: step2,
                    assets: assets,
                    mediaRepository: mediaRepository,
                  ),
                ),
                const SizedBox(width: 12),
                arrow(),
                const SizedBox(width: 12),
                SizedBox(
                  width: columnWidth,
                  child: _JourneyStepColumn(
                    label: 'Steg 3',
                    description: 'Fördjupad förståelse och mognad',
                    courses: step3,
                    assets: assets,
                    mediaRepository: mediaRepository,
                  ),
                ),
              ],
            );

            if (isWide) return row;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: row,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _JourneyStepColumn extends StatelessWidget {
  const _JourneyStepColumn({
    required this.label,
    required this.description,
    required this.courses,
    required this.assets,
    required this.mediaRepository,
  });

  final String label;
  final String description;
  final List<CourseSummary> courses;
  final BackendAssetResolver assets;
  final MediaRepository mediaRepository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      opacity: 0.12,
      sigmaX: 10,
      sigmaY: 10,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      borderColor: Colors.white.withValues(alpha: 0.16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: DesignTokens.bodyTextColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: DesignTokens.bodyTextColor.withValues(alpha: 0.72),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (courses.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 10),
              child: Text(
                'Fler kurser kommer snart.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: DesignTokens.bodyTextColor.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Column(
              children: [
                for (final course in courses) ...[
                  _JourneyCourseCard(
                    course: course,
                    assets: assets,
                    mediaRepository: mediaRepository,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _IntroMiniCourseCard extends StatelessWidget {
  const _IntroMiniCourseCard({
    required this.course,
    required this.assets,
    required this.mediaRepository,
  });

  final CourseSummary course;
  final BackendAssetResolver assets;
  final MediaRepository mediaRepository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(16);
    final slug = (course.slug ?? '').trim();
    final resolvedCover = _resolveCoverUrl(mediaRepository, course.coverUrl);
    final coverProvider = CourseCoverAssets.resolve(
      assets: assets,
      slug: slug,
      coverUrl: resolvedCover,
    );
    final imageProvider = coverProvider ?? AppImages.logo;
    final isFallbackLogo = coverProvider == null;
    final isIntro = course.isFreeIntro;
    final priceLabel = formatCoursePriceFromOre(
      amountOre: course.priceCents ?? 0,
      isFreeIntro: isIntro,
      debugContext: slug.isEmpty ? 'CourseCatalogPage' : 'slug=$slug',
    );

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
          padding: EdgeInsets.zero,
          opacity: 0.18,
          sigmaX: 12,
          sigmaY: 12,
          borderRadius: radius,
          borderColor: Colors.white.withValues(alpha: 0.16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (SafeMedia.enabled) {
                        SafeMedia.markThumbnails();
                      }
                      final cacheWidth = SafeMedia.cacheDimension(
                        context,
                        constraints.maxWidth,
                        max: 800,
                      );
                      final cacheHeight = SafeMedia.cacheDimension(
                        context,
                        constraints.maxHeight,
                        max: 800,
                      );
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(isFallbackLogo ? 14 : 0),
                          child: Image(
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
                        ),
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isIntro) ...[
                        Text(
                          course.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: DesignTokens.bodyTextColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        const CourseIntroBadge(),
                      ] else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                course.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: DesignTokens.bodyTextColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              priceLabel,
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: DesignTokens.bodyTextColor.withValues(
                                  alpha: 0.72,
                                ),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JourneyCourseCard extends StatelessWidget {
  const _JourneyCourseCard({
    required this.course,
    required this.assets,
    required this.mediaRepository,
  });

  final CourseSummary course;
  final BackendAssetResolver assets;
  final MediaRepository mediaRepository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slug = (course.slug ?? '').trim();
    final resolvedCover = _resolveCoverUrl(mediaRepository, course.coverUrl);
    final coverProvider = CourseCoverAssets.resolve(
      assets: assets,
      slug: slug,
      coverUrl: resolvedCover,
    );
    final imageProvider = coverProvider ?? AppImages.logo;
    final isFallbackLogo = coverProvider == null;

    final radius = BorderRadius.circular(18);
    final isIntro = course.isFreeIntro;
    final priceLabel = formatCoursePriceFromOre(
      amountOre: course.priceCents ?? 0,
      isFreeIntro: isIntro,
      debugContext: slug.isEmpty ? 'CourseCatalogPage' : 'slug=$slug',
    );

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
          padding: EdgeInsets.zero,
          opacity: 0.18,
          sigmaX: 12,
          sigmaY: 12,
          borderRadius: radius,
          borderColor: Colors.white.withValues(alpha: 0.16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
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
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(isFallbackLogo ? 18 : 0),
                          child: Image(
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
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            course.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: DesignTokens.bodyTextColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        isIntro
                            ? const CourseIntroBadge()
                            : Text(
                                priceLabel,
                                textAlign: TextAlign.right,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: DesignTokens.bodyTextColor.withValues(
                                    alpha: 0.72,
                                  ),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ],
                    ),
                    if ((course.description ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      CourseDescriptionText(
                        course.description!.trim(),
                        baseStyle: theme.textTheme.bodyMedium,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActAveliProSection extends StatelessWidget {
  const _ActAveliProSection({required this.isEnabled});

  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabledHint = 'Tillgängligt när du har slutfört ett tredje steg';

    return GlassCard(
      opacity: 0.1,
      sigmaX: 10,
      sigmaY: 10,
      borderColor: Colors.white.withValues(alpha: 0.16),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            child: Opacity(
              opacity: 0.18,
              child: Image(
                image: AppImages.logo,
                width: 64,
                height: 64,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                'När du är redo att bära det vidare',
                baseStyle: theme.textTheme.titleLarge,
                fontWeight: FontWeight.w800,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Text(
                'För vissa stannar resan vid personlig fördjupning.\n'
                'För andra växer en vilja att dela, guida och stötta.\n\n'
                'När du har gått färdigt ett tredje steg i en kurs\n'
                'kan du ansöka om att bli Aveli-Pro\n'
                'och börja dela den kunskap du kultiverat – på dina villkor.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: isEnabled
                    ? () => _showAveliProDialog(context)
                    : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  disabledBackgroundColor: const Color(0xFFB9B9B9),
                  disabledForegroundColor: const Color(0xFF4F4F4F),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Ansök om Aveli-Pro',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (!isEnabled) ...[
                const SizedBox(height: 10),
                MetaText(
                  disabledHint,
                  baseStyle: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showAveliProDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aveli-Pro'),
        content: const Text(
          'Tack.\n\n'
          'Vi öppnar ansökningsflödet stegvis. '
          'Du kan redan nu fortsätta din resa i kurserna, '
          'så återkommer vi med nästa steg när det är dags.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Stäng'),
          ),
        ],
      ),
    );
  }
}

String? _resolveCoverUrl(MediaRepository repository, String? path) {
  if (path == null || path.trim().isEmpty) return null;
  try {
    return repository.resolveUrl(path);
  } catch (_) {
    return path;
  }
}
