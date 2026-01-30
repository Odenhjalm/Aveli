import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/bootstrap/safe_media.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/shared/theme/design_tokens.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import 'package:aveli/shared/utils/course_cover_assets.dart';
import 'package:aveli/shared/widgets/card_text.dart';
import 'package:aveli/shared/widgets/course_intro_badge.dart';
import 'package:aveli/shared/widgets/effects_backdrop_filter.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/shared/widgets/hero_badge.dart';
import 'package:aveli/shared/widgets/semantic_text.dart';

enum CoursesShowcaseLayout { vertical }

class CoursesShowcaseDesktop {
  const CoursesShowcaseDesktop({required this.columns, required this.rows})
    : assert(columns > 0),
      assert(rows > 0);

  final int columns;
  final int rows;

  int get maxItems => columns * rows;
}

/// Shared course section used on both Landing and Home.
///
/// IMPORTANT: Keep the card UI verbatim to the Landing page course tiles.
class CoursesShowcaseSection extends ConsumerWidget {
  const CoursesShowcaseSection({
    super.key,
    required this.title,
    this.layout = CoursesShowcaseLayout.vertical,
    this.desktop,
    this.includeOuterChrome = true,
    this.showHeroBadge = true,
    this.includeStudioCourses = true,
    this.ctaGradient,
    this.tileScale = 1.0,
    this.tileTextColor,
    this.introBadgeVariant = CourseIntroBadgeVariant.badge,
    this.gridCrossAxisSpacing = 12,
    this.gridMainAxisSpacing = 12,
  }) : assert(tileScale > 0),
       assert(tileScale <= 1.0),
       assert(gridCrossAxisSpacing >= 0),
       assert(gridMainAxisSpacing >= 0);

  final String title;
  final CoursesShowcaseLayout layout;
  final CoursesShowcaseDesktop? desktop;
  final bool includeOuterChrome;
  final bool showHeroBadge;
  final bool includeStudioCourses;
  final Gradient? ctaGradient;
  final double tileScale;
  final Color? tileTextColor;
  final CourseIntroBadgeVariant introBadgeVariant;
  final double gridCrossAxisSpacing;
  final double gridMainAxisSpacing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final assets = ref.watch(backendAssetResolverProvider);
    final mediaRepository = ref.watch(mediaRepositoryProvider);

    final popularAsync = ref.watch(landing.popularCoursesProvider);
    final myStudioAsync = includeStudioCourses
        ? ref.watch(landing.myStudioCoursesProvider)
        : const AsyncData(landing.LandingSectionState(items: []));

    final fallbackCoursesAsync = ref.watch(coursesProvider);

    final loading = popularAsync.isLoading || myStudioAsync.isLoading;
    final popular =
        popularAsync.valueOrNull?.items ?? const <Map<String, dynamic>>[];
    final myStudio =
        myStudioAsync.valueOrNull?.items ?? const <Map<String, dynamic>>[];

    var items = _mergePopularWithMyCourses(popular, myStudio, mediaRepository);

    if (items.isEmpty) {
      final fallback =
          fallbackCoursesAsync.valueOrNull ?? const <CourseSummary>[];
      if (fallback.isNotEmpty) {
        items = _normalizeCourseCovers(
          _mapCourseSummaries(fallback),
          mediaRepository,
        );
      }
    }

    final visible = desktop == null
        ? items
        : items.take(desktop!.maxItems).toList(growable: false);

    final sectionTextColor = tileTextColor;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeroBadge) ...[
          const Center(
            child: HeroBadge(
              text: 'Sveriges ledande plattform för andlig utveckling',
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 14),
        sectionTextColor == null
            ? SectionHeading(
                title,
                baseStyle: t.headlineSmall,
                fontWeight: FontWeight.w800,
              )
            : Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (t.headlineSmall ?? const TextStyle()).copyWith(
                  color: sectionTextColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
        const SizedBox(height: 4),
        sectionTextColor == null
            ? MetaText('Se vad andra gillar just nu.', baseStyle: t.bodyLarge)
            : Text(
                'Se vad andra gillar just nu.',
                style: (t.bodyLarge ?? t.bodyMedium ?? const TextStyle())
                    .copyWith(color: sectionTextColor),
              ),
        const SizedBox(height: 16),
        GlassCard(
          child: loading
              ? const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()),
                )
              : visible.isEmpty
              ? sectionTextColor == null
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: MetaText('Inga kurser ännu.'),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Inga kurser ännu.',
                          style: (t.bodyMedium ?? const TextStyle()).copyWith(
                            color: sectionTextColor,
                          ),
                        ),
                      )
              : _buildLayout(
                  context,
                  visible,
                  assets,
                  layout: layout,
                  desktop: desktop,
                  ctaGradient: ctaGradient,
                  tileScale: tileScale,
                  tileTextColor: tileTextColor,
                  introBadgeVariant: introBadgeVariant,
                  gridCrossAxisSpacing: gridCrossAxisSpacing,
                  gridMainAxisSpacing: gridMainAxisSpacing,
                ),
        ),
      ],
    );

    if (!includeOuterChrome) {
      return content;
    }

    return Container(
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: content,
          ),
        ),
      ),
    );
  }

  static List<Map<String, dynamic>> _mergePopularWithMyCourses(
    List<Map<String, dynamic>> popular,
    List<Map<String, dynamic>> myCourses,
    MediaRepository mediaRepository,
  ) {
    final combined = <Map<String, dynamic>>[];
    final seen = <String>{};

    String keyFor(Map<String, dynamic> map) {
      final slug = (map['slug'] as String?)?.trim();
      if (slug != null && slug.isNotEmpty) return slug;
      final id = (map['id'] as String?)?.trim();
      if (id != null && id.isNotEmpty) return id;
      return map.hashCode.toString();
    }

    void addCourse(Map<String, dynamic> map) {
      final key = keyFor(map);
      if (seen.contains(key)) return;
      seen.add(key);
      combined.add(Map<String, dynamic>.from(map));
    }

    final ownCourses = myCourses
        .where((course) => course['is_published'] == true)
        .toList(growable: false);

    if (ownCourses.isNotEmpty) {
      for (final course in ownCourses) {
        addCourse(course);
      }
      return _normalizeCourseCovers(combined, mediaRepository);
    }

    for (final course in popular) {
      addCourse(course);
    }

    return _normalizeCourseCovers(combined, mediaRepository);
  }

  static List<Map<String, dynamic>> _normalizeCourseCovers(
    List<Map<String, dynamic>> courses,
    MediaRepository mediaRepository,
  ) {
    for (final course in courses) {
      final cover = course['cover_url'] as String?;
      if (cover == null || cover.isEmpty) continue;
      try {
        course['cover_url'] = mediaRepository.resolveUrl(cover);
      } catch (_) {
        // Keep original value on resolve failure.
      }
    }
    return courses;
  }

  static List<Map<String, dynamic>> _mapCourseSummaries(
    List<CourseSummary> courses,
  ) {
    return courses
        .where((course) => (course.slug ?? '').isNotEmpty)
        .map((course) {
          return {
            'title': course.title,
            'description': course.description ?? '',
            'slug': course.slug ?? '',
            'is_free_intro': course.isFreeIntro,
            'cover_url': course.coverUrl,
          };
        })
        .toList(growable: false);
  }

  static Widget _buildLayout(
    BuildContext context,
    List<Map<String, dynamic>> items,
    BackendAssetResolver assets, {
    required CoursesShowcaseLayout layout,
    CoursesShowcaseDesktop? desktop,
    Gradient? ctaGradient,
    required double tileScale,
    Color? tileTextColor,
    required CourseIntroBadgeVariant introBadgeVariant,
    required double gridCrossAxisSpacing,
    required double gridMainAxisSpacing,
  }) {
    switch (layout) {
      case CoursesShowcaseLayout.vertical:
        return LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final cross = w >= 900
                ? (desktop?.columns ?? 3)
                : (w >= 600 ? 2 : 1);
            final crossAxisSpacing = gridCrossAxisSpacing;
            final mainAxisSpacing = gridMainAxisSpacing;
            final availableWidth = w - crossAxisSpacing * (cross - 1);
            final itemWidth = cross == 0 ? w : availableWidth / cross;
            const mediaAspectRatio = 16 / 9;
            final mediaHeight = itemWidth / mediaAspectRatio;
            const reservedHeight = 250.0;
            final tileHeight = mediaHeight + reservedHeight;
            final computedAspectRatio = itemWidth / tileHeight;
            final childAspectRatio = computedAspectRatio
                .clamp(0.72, 1.05)
                .toDouble();

            final grid = GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cross,
                crossAxisSpacing: crossAxisSpacing,
                mainAxisSpacing: mainAxisSpacing,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (_, i) => _CourseTileGlass(
                course: items[i],
                index: i,
                assets: assets,
                ctaGradient: ctaGradient,
                textColor: tileTextColor,
                introBadgeVariant: introBadgeVariant,
              ),
            );

            if (tileScale == 1.0 || cross == 0) return grid;

            final scaledWidth =
                tileScale * availableWidth + crossAxisSpacing * (cross - 1);
            return SizedBox(width: scaledWidth, child: grid);
          },
        );
    }
  }
}

// ---- Section item widgets (glass style) ----

class _CourseTileGlass extends StatelessWidget {
  final Map<String, dynamic> course;
  final int index;
  final BackendAssetResolver assets;
  final Gradient? ctaGradient;
  final Color? textColor;
  final CourseIntroBadgeVariant introBadgeVariant;
  const _CourseTileGlass({
    required this.course,
    required this.index,
    required this.assets,
    this.ctaGradient,
    this.textColor,
    required this.introBadgeVariant,
  });

  @override
  Widget build(BuildContext context) {
    final title = (course['title'] as String?) ?? 'Kurs';
    final desc = (course['description'] as String?) ?? '';
    final cover = (course['cover_url'] as String?) ?? '';
    final slug = (course['slug'] as String?) ?? '';
    final isIntro = course['is_free_intro'] == true;
    final coverProvider = CourseCoverAssets.resolve(
      assets: assets,
      slug: cover.isEmpty ? slug : null,
      coverUrl: cover,
    );
    final isFallbackLogo = coverProvider == null;
    final imageProvider = coverProvider ?? AppImages.logo;

    final theme = Theme.of(context);
    final baseColor = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.03)
        : Colors.white.withValues(alpha: 0.18);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      color: textColor ?? DesignTokens.bodyTextColor,
      fontWeight: FontWeight.w800,
    );

    void openCourse() {
      if (slug.isNotEmpty) {
        context.pushNamed(AppRoute.course, pathParameters: {'slug': slug});
      } else {
        context.pushNamed(AppRoute.courseIntro);
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: openCourse,
        borderRadius: BorderRadius.circular(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: EffectsBackdropFilter(
            sigmaX: 18,
            sigmaY: 18,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [baseColor, baseColor.withValues(alpha: 0.32)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF000000).withValues(alpha: 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.white.withValues(alpha: 0.18),
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
                                  fit: isFallbackLogo
                                      ? BoxFit.contain
                                      : BoxFit.cover,
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
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle,
                                ),
                              ),
                              if (isIntro) const SizedBox(width: 8),
                              if (isIntro)
                                CourseIntroBadge(variant: introBadgeVariant),
                            ],
                          ),
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            CourseDescriptionText(
                              desc,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              baseStyle: theme.textTheme.bodyMedium,
                              color: textColor,
                            ),
                          ],
                          const Spacer(),
                          Align(
                            alignment: Alignment.centerRight,
                            child: GradientButton(
                              onPressed: openCourse,
                              gradient: ctaGradient,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              child: const Text(
                                'Öppna',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
