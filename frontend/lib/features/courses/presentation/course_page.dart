import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/payments/presentation/paywall_prompt.dart';
import 'package:aveli/features/paywall/application/pricing_providers.dart';
import 'package:aveli/features/paywall/data/course_pricing_api.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/shared/utils/course_cover_resolver.dart';
import 'package:aveli/shared/utils/course_journey_step.dart';
import 'package:aveli/shared/utils/money.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/glass_card.dart';

class CoursePage extends ConsumerStatefulWidget {
  const CoursePage({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends ConsumerState<CoursePage> {
  bool _ordering = false;

  @override
  Widget build(BuildContext context) {
    final asyncDetail = ref.watch(courseDetailProvider(widget.slug));
    return asyncDetail.when(
      loading: () => const AppScaffold(
        title: 'Kurs',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AppScaffold(
        title: 'Kurs',
        body: Center(child: Text(_friendlyError(error))),
      ),
      data: (detail) {
        final slug = (detail.course.slug?.isNotEmpty ?? false)
            ? detail.course.slug!
            : widget.slug;
        final cover = resolveCourseSummaryCover(
          detail.course,
          ref.read(mediaRepositoryProvider),
        );
        final pricingAsync = ref.watch(coursePricingProvider(slug));
        final courseStateAsync = ref.watch(
          courseStateProvider(detail.course.id),
        );
        return _CourseContent(
          detail: detail,
          courseStateAsync: courseStateAsync,
          coverUrl: cover.imageUrl,
          onEnroll: () => _handleEnroll(detail),
          onOpenLesson: _openLesson,
          enrollState: ref.watch(enrollProvider(detail.course.id)),
          buyButton: _buildBuyButton(
            course: detail.course,
            courseStateAsync: courseStateAsync,
            courseSlug: slug,
            pricingAsync: pricingAsync,
          ),
        );
      },
    );
  }

  Future<void> _handleEnroll(CourseDetailData detail) async {
    if (!_ensureAuthenticated(
      message: 'Logga in för att starta introduktionen.',
    )) {
      return;
    }
    final notifier = ref.read(enrollProvider(detail.course.id).notifier);
    await notifier.enroll();
    final state = ref.read(enrollProvider(detail.course.id));
    state.when(
      data: (courseState) {
        if (!mounted || !context.mounted) return;
        if (courseState?.hasEnrollment == true) {
          showSnack(context, 'Du är nu anmäld till kursen.');
        }
        ref.invalidate(courseStateProvider(detail.course.id));
        ref.invalidate(courseDetailProvider(widget.slug));
      },
      error: (error, _) {
        if (!mounted || !context.mounted) return;
        showSnack(context, 'Kunde inte anmäla: ${_friendlyError(error)}');
      },
      loading: () {},
    );
  }

  void _openLesson(String lessonId) {
    if (!mounted || !context.mounted) return;
    context.pushNamed(AppRoute.lesson, pathParameters: {'id': lessonId});
  }

  Widget? _buildBuyButton({
    required CourseSummary course,
    required AsyncValue<CourseAccessData?> courseStateAsync,
    required String courseSlug,
    required AsyncValue<CoursePricing> pricingAsync,
  }) {
    final courseState = courseStateAsync.valueOrNull;
    final hasEnrollment = courseState?.hasEnrollment == true;
    final isIntroCourse = course.step == CourseJourneyStep.intro;
    final fallbackPrice = pricingAsync.maybeWhen(
      data: (pricing) => pricing.amountCents,
      orElse: () => null,
    );
    final priceCents = course.priceCents ?? fallbackPrice ?? 0;
    final canPurchase = !isIntroCourse && !hasEnrollment && priceCents > 0;
    if (!canPurchase) {
      return null;
    }

    return pricingAsync.when(
      loading: () => const SizedBox(
        height: 44,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => TextButton(
        onPressed: () => ref.refresh(coursePricingProvider(courseSlug)),
        child: const Text('Ladda pris igen'),
      ),
      data: (pricing) {
        final formatted = formatCoursePriceFromOre(
          amountOre: pricing.amountCents,
          isFreeIntro: false,
          debugContext: courseSlug.isEmpty ? 'CoursePage' : 'slug=$courseSlug',
        );
        return FilledButton(
          onPressed: _ordering ? null : () => _startCourseCheckout(courseSlug),
          child: _ordering
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Köp hela kursen ($formatted)'),
        );
      },
    );
  }

  Future<void> _startCourseCheckout(String slug) async {
    if (!_ensureAuthenticated()) return;
    setState(() => _ordering = true);
    try {
      final checkoutApi = ref.read(checkoutApiProvider);
      final url = await checkoutApi.startCourseCheckout(slug: slug);
      if (!mounted || !context.mounted) return;
      context.push(RoutePath.checkout, extra: url);
    } catch (error) {
      if (!mounted || !context.mounted) return;
      showSnack(
        context,
        'Kunde inte starta betalning: ${_friendlyError(error)}',
      );
    } finally {
      if (mounted) setState(() => _ordering = false);
    }
  }

  bool _ensureAuthenticated({
    String message = 'Logga in för att fortsätta med köpet.',
  }) {
    final authState = ref.read(authControllerProvider);
    if (authState.isAuthenticated) {
      return true;
    }
    if (!mounted || !context.mounted) return false;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    final redirectTarget = _currentRoute();
    context.goNamed(
      AppRoute.login,
      queryParameters: {'redirect': redirectTarget},
    );
    return false;
  }

  String _currentRoute() {
    try {
      return GoRouterState.of(context).uri.toString();
    } catch (_) {
      return RoutePath.home;
    }
  }

  String _friendlyError(Object error) => AppFailure.from(error).message;
}

class _CourseContent extends StatelessWidget {
  const _CourseContent({
    required this.detail,
    required this.courseStateAsync,
    required this.coverUrl,
    required this.onEnroll,
    required this.onOpenLesson,
    required this.enrollState,
    required this.buyButton,
  });

  final CourseDetailData detail;
  final AsyncValue<CourseAccessData?> courseStateAsync;
  final String? coverUrl;
  final VoidCallback onEnroll;
  final ValueChanged<String> onOpenLesson;
  final AsyncValue<CourseAccessData?> enrollState;
  final Widget? buyButton;

  @override
  Widget build(BuildContext context) {
    final course = detail.course;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final courseState = courseStateAsync.valueOrNull;
    final hasEnrollment = courseState?.hasEnrollment == true;
    final currentUnlockPosition = courseState?.currentUnlockPosition ?? 0;
    final isIntroCourse = course.step == CourseJourneyStep.intro;
    final lessons = _visibleCourseLessons(detail.lessons);
    final unlockedLessons = lessons
        .where((lesson) => lesson.position <= currentUnlockPosition)
        .toList(growable: false);
    final isEnrolling = enrollState.isLoading;
    final enrollError = enrollState.whenOrNull(error: (error, _) => error);

    Widget? primaryCta;
    if (hasEnrollment && unlockedLessons.isNotEmpty) {
      primaryCta = FilledButton(
        onPressed: () => onOpenLesson(unlockedLessons.first.id),
        child: const Text('Fortsätt kursen'),
      );
    } else if (isIntroCourse && !hasEnrollment) {
      primaryCta = ElevatedButton(
        onPressed: isEnrolling ? null : onEnroll,
        child: isEnrolling
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Starta introduktion'),
      );
    } else if (buyButton != null) {
      primaryCta = SizedBox(
        width: double.infinity,
        height: 48,
        child: buyButton,
      );
    } else if (hasEnrollment) {
      primaryCta = const FilledButton(
        onPressed: null,
        child: Text('Kurs aktiverad'),
      );
    }

    return AppScaffold(
      title: course.title,
      body: ListView(
        children: [
          if (coverUrl != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Image.network(coverUrl!, fit: BoxFit.contain),
                ),
              ),
            ),
          if (coverUrl != null) const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(20),
            opacity: 0.18,
            borderRadius: BorderRadius.circular(26),
            borderColor: Colors.white.withValues(alpha: 0.18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.title,
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                if (primaryCta != null)
                  SizedBox(width: double.infinity, child: primaryCta),
                if (hasEnrollment) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Upplåsta lektioner: $currentUnlockPosition',
                    style: t.bodySmall,
                  ),
                ],
                if (enrollError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _friendlyError(enrollError),
                      style: t.bodyMedium?.copyWith(color: cs.error),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (lessons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassCard(
                padding: const EdgeInsets.all(12),
                opacity: 0.16,
                borderRadius: BorderRadius.circular(22),
                borderColor: Colors.white.withValues(alpha: 0.16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...lessons.map((lesson) {
                      final isLocked =
                          !hasEnrollment ||
                          lesson.position > currentUnlockPosition;
                      return ListTile(
                        leading: Icon(
                          isLocked
                              ? Icons.lock_outline_rounded
                              : Icons.play_circle_outline_rounded,
                        ),
                        title: Text(lesson.title),
                        subtitle: isLocked
                            ? const Text('Låst innehåll')
                            : Text('Lektion ${lesson.position}'),
                        enabled: !isLocked,
                        onTap: () =>
                            _handleLessonTap(context, lesson, detail, isLocked),
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleLessonTap(
    BuildContext context,
    LessonSummary lesson,
    CourseDetailData detail,
    bool isLocked,
  ) {
    if (!isLocked) {
      onOpenLesson(lesson.id);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Material(
              color: Theme.of(ctx).scaffoldBackgroundColor,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: PaywallPrompt(courseId: detail.course.id),
              ),
            ),
          ),
        );
      },
    );
  }

  String _friendlyError(Object error) => AppFailure.from(error).message;
}

List<LessonSummary> _visibleCourseLessons(List<LessonSummary> lessons) {
  final visible = lessons
      .where(
        (lesson) =>
            lesson.title.isNotEmpty && !lesson.title.trim().startsWith('_'),
      )
      .toList(growable: false);
  visible.sort((a, b) => a.position.compareTo(b.position));
  return visible;
}
