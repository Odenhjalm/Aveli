import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:aveli/core/bootstrap/safe_media.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import 'package:aveli/shared/utils/course_cover_assets.dart';
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
    final introAsync = ref.watch(landing.introCoursesProvider);
    final popularAsync = ref.watch(landing.popularCoursesProvider);

    final intro =
        introAsync.valueOrNull?.items ?? const <Map<String, dynamic>>[];
    final popular =
        popularAsync.valueOrNull?.items ?? const <Map<String, dynamic>>[];

    final free = _dedupeCourses([
      ...intro.where((course) => course['is_free_intro'] == true),
      ...popular.where((course) => course['is_free_intro'] == true),
    ]);

    final journey = popular
        .where((course) => course['is_free_intro'] != true)
        .toList(growable: false);

    final steps = _splitJourneySteps(journey);

    final publishedCoursesAsync = ref.watch(coursesProvider);
    final slugToId = <String, String>{};
    for (final course in publishedCoursesAsync.valueOrNull ?? const []) {
      final slug = (course.slug ?? '').trim();
      if (slug.isEmpty) continue;
      slugToId[slug] = course.id;
    }

    final step3CourseIds = <String>{};
    for (final course in steps.step3) {
      final id = _resolveCourseId(course, slugToId: slugToId);
      if (id != null && id.isNotEmpty) {
        step3CourseIds.add(id);
      }
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

    final isLoading = introAsync.isLoading || popularAsync.isLoading;
    final Object? error = introAsync.error ?? popularAsync.error;

    final hasAnyCourses = free.isNotEmpty || journey.isNotEmpty;

    final content = isLoading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? _ErrorState(error: error)
        : !hasAnyCourses
        ? _EmptyState(theme: theme)
        : _CourseJourney(
            freeCourses: free,
            step1Courses: steps.step1,
            step2Courses: steps.step2,
            step3Courses: steps.step3,
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

  static List<Map<String, dynamic>> _dedupeCourses(
    Iterable<Map<String, dynamic>> courses,
  ) {
    final seen = <String>{};
    final items = <Map<String, dynamic>>[];

    for (final raw in courses) {
      final course = Map<String, dynamic>.from(raw);
      final slug = (course['slug'] as String?)?.trim();
      final id = (course['id'] as String?)?.trim();
      final key = slug?.isNotEmpty == true
          ? slug!
          : (id?.isNotEmpty == true ? id! : course.hashCode.toString());
      if (seen.contains(key)) continue;
      seen.add(key);
      items.add(course);
    }

    return items;
  }

  static _JourneySteps _splitJourneySteps(List<Map<String, dynamic>> courses) {
    final step1 = <Map<String, dynamic>>[];
    final step2 = <Map<String, dynamic>>[];
    final step3 = <Map<String, dynamic>>[];

    for (final course in courses) {
      final step = _resolveJourneyStep(course) ?? 1;
      switch (step) {
        case 1:
          step1.add(course);
          break;
        case 2:
          step2.add(course);
          break;
        case 3:
          step3.add(course);
          break;
      }
    }

    return _JourneySteps(step1: step1, step2: step2, step3: step3);
  }

  static int? _resolveJourneyStep(Map<String, dynamic> course) {
    final branch = (course['branch'] as String?)?.toLowerCase() ?? '';
    final title = (course['title'] as String?)?.toLowerCase() ?? '';
    final slug = (course['slug'] as String?)?.toLowerCase() ?? '';
    final haystack = '$branch $title $slug';

    int? match(RegExp exp) {
      final m = exp.firstMatch(haystack);
      if (m == null) return null;
      final value = int.tryParse(m.group(1) ?? '');
      if (value == null) return null;
      if (value < 1 || value > 3) return null;
      return value;
    }

    if (branch.trim() == '1') return 1;
    if (branch.trim() == '2') return 2;
    if (branch.trim() == '3') return 3;

    return match(RegExp(r'\\bsteg\\s*([1-3])\\b')) ??
        match(RegExp(r'\\bstep\\s*([1-3])\\b')) ??
        match(RegExp(r'\\bnivå\\s*([1-3])\\b')) ??
        match(RegExp(r'\\blevel\\s*([1-3])\\b'));
  }

  static String? _resolveCourseId(
    Map<String, dynamic> course, {
    required Map<String, String> slugToId,
  }) {
    String? normalize(dynamic value) {
      if (value == null) return null;
      final raw = value is String ? value : value.toString();
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final id = normalize(course['id']) ?? normalize(course['course_id']);
    if (id != null) return id;

    final slug = normalize(course['slug']);
    if (slug == null) return null;
    return slugToId[slug];
  }
}

class _JourneySteps {
  const _JourneySteps({
    required this.step1,
    required this.step2,
    required this.step3,
  });

  final List<Map<String, dynamic>> step1;
  final List<Map<String, dynamic>> step2;
  final List<Map<String, dynamic>> step3;
}

class _CourseJourney extends StatelessWidget {
  const _CourseJourney({
    required this.freeCourses,
    required this.step1Courses,
    required this.step2Courses,
    required this.step3Courses,
    required this.assets,
    required this.canApplyForPro,
    required this.proEligibilityHint,
  });

  final List<Map<String, dynamic>> freeCourses;
  final List<Map<String, dynamic>> step1Courses;
  final List<Map<String, dynamic>> step2Courses;
  final List<Map<String, dynamic>> step3Courses;
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
            child: _IntroWindow(courses: freeCourses, assets: assets),
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

  final List<Map<String, dynamic>> courses;
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

  final Map<String, dynamic> course;
  final BackendAssetResolver assets;

  @override
  Widget build(BuildContext context) {
    final title = (course['title'] as String?)?.trim();
    final slug = (course['slug'] as String?)?.trim() ?? '';
    final coverUrl = (course['cover_url'] as String?)?.trim();

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
                title?.isNotEmpty == true ? title! : 'Introduktion',
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

  final List<Map<String, dynamic>> step1Courses;
  final List<Map<String, dynamic>> step2Courses;
  final List<Map<String, dynamic>> step3Courses;
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
  final List<Map<String, dynamic>> courses;
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

  final Map<String, dynamic> course;
  final bool showPrice;
  final BackendAssetResolver assets;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final title = (course['title'] as String?)?.trim();
    final description = (course['description'] as String?)?.trim() ?? '';
    final slug = (course['slug'] as String?)?.trim() ?? '';

    final priceCents =
        _asInt(course['price_amount_cents']) ?? _asInt(course['price_cents']);
    final currency =
        (course['currency'] as String?)?.trim().toLowerCase() ?? 'sek';
    final priceLabel = showPrice
        ? _formatPrice(priceCents, currency: currency)
        : null;

    final coverUrl = (course['cover_url'] as String?)?.trim();
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
                title?.isNotEmpty == true ? title! : 'Kurs',
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

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
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
