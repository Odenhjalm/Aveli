import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/payments/presentation/paywall_prompt.dart';
import 'package:aveli/features/paywall/presentation/paywall_gate.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/features/paywall/application/pricing_providers.dart';
import 'package:aveli/features/paywall/data/course_pricing_api.dart';
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
    if (widget.slug == 'vit_magi') {
      return const AppScaffold(
        title: 'Vit Magi',
        body: PaywallGate(courseSlug: 'vit_magi', unlocked: _VitMagiContent()),
      );
    }

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
        final pricingAsync = ref.watch(coursePricingProvider(slug));
        final buyButton = _buildBuyButton(
          courseSlug: slug,
          pricingAsync: pricingAsync,
          detail: detail,
        );
        return _CourseContent(
          detail: detail,
          buyButton: buyButton,
          onEnroll: () => _handleEnroll(detail),
          onRefreshOrderStatus: () async {
            final repo = ref.read(coursesRepositoryProvider);
            await repo.latestOrderForCourse(detail.course.id);
            ref.invalidate(courseDetailProvider(widget.slug));
          },
          enrollState: ref.watch(enrollProvider(detail.course.id)),
          subscriptionsEnabled: ref
              .watch(appConfigProvider)
              .subscriptionsEnabled,
        );
      },
    );
  }

  Future<void> _handleEnroll(CourseDetailData detail) async {
    final notifier = ref.read(enrollProvider(detail.course.id).notifier);
    await notifier.enroll();
    final state = ref.read(enrollProvider(detail.course.id));
    state.when(
      data: (_) {
        if (!mounted || !context.mounted) return;
        showSnack(context, 'Du är nu anmäld till introduktionen.');
        ref.invalidate(courseDetailProvider(widget.slug));
      },
      error: (error, _) {
        if (!mounted || !context.mounted) return;
        showSnack(context, 'Kunde inte anmäla: ${_friendlyError(error)}');
      },
      loading: () {},
    );
  }

  Widget _buildBuyButton({
    required String courseSlug,
    required AsyncValue<CoursePricing> pricingAsync,
    required CourseDetailData detail,
  }) {
    final hasAccess = detail.hasAccess;
    final hasSubscription =
        ref.watch(appConfigProvider).subscriptionsEnabled &&
        detail.hasActiveSubscription;
    final isEnrolled = detail.isEnrolled;
    final fallbackPrice = pricingAsync.maybeWhen(
      data: (pricing) => pricing.amountCents,
      orElse: () => null,
    );
    final priceCents = detail.course.priceCents ?? fallbackPrice ?? 0;
    final canPurchase = priceCents > 0 && !hasAccess;

    if (!canPurchase) {
      final label = hasAccess
          ? (hasSubscription && !isEnrolled
                ? 'Prenumeration aktiv'
                : 'Åtkomst aktiverad')
          : 'Kursen kan inte köpas just nu';
      return FilledButton(onPressed: null, child: Text(label));
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
        final amount = (pricing.amountCents / 100).round();
        final formatted = NumberFormat.currency(
          locale: 'sv_SE',
          symbol: 'kr',
          decimalDigits: 0,
        ).format(amount);
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

  bool _ensureAuthenticated() {
    final authState = ref.read(authControllerProvider);
    if (authState.isAuthenticated) {
      return true;
    }
    if (!mounted || !context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logga in för att fortsätta med köpet.')),
    );
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

class _VitMagiContent extends StatelessWidget {
  const _VitMagiContent();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        Text(
          'Välkommen till Vit Magi',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 12),
        Text(
          'Du har låst upp kursen. Utforska materialen och följ instruktionerna '
          'för att komma igång.',
        ),
      ],
    );
  }
}

class _CourseContent extends StatelessWidget {
  const _CourseContent({
    required this.detail,
    required this.onEnroll,
    required this.onRefreshOrderStatus,
    required this.enrollState,
    required this.subscriptionsEnabled,
    required this.buyButton,
  });

  final CourseDetailData detail;
  final VoidCallback onEnroll;
  final Future<void> Function() onRefreshOrderStatus;
  final AsyncValue<void> enrollState;
  final bool subscriptionsEnabled;
  final Widget buyButton;

  String _orderStatusLabel(String status) {
    final normalized = status.toLowerCase();
    return switch (normalized) {
      'paid' => 'Betald',
      'pending' => 'Pågår',
      'failed' => 'Misslyckad',
      'canceled' || 'cancelled' => 'Avbruten',
      _ => status.isEmpty ? 'Okänd' : status,
    };
  }

  @override
  Widget build(BuildContext context) {
    final course = detail.course;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final priceCents = course.priceCents ?? 0;
    final hasAccess = detail.hasAccess;
    final isEnrolled = detail.isEnrolled;
    final hasSubscription =
        subscriptionsEnabled && detail.hasActiveSubscription;
    final enrolledText = hasAccess
        ? (hasSubscription && !isEnrolled
              ? '• Prenumeration aktiv'
              : '• Du är anmäld')
        : '';
    final isEnrolling = enrollState.isLoading;
    final enrollError = enrollState.whenOrNull(error: (error, _) => error);
    final canPurchase = priceCents > 0 && !hasAccess;

    return AppScaffold(
      title: course.title,
      body: ListView(
        children: [
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
                const SizedBox(height: 8),
                if (course.description != null)
                  Text(
                    course.description!,
                    style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isEnrolling ? null : onEnroll,
                        child: isEnrolling
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Starta gratis intro'),
                      ),
                    ),
                    if (priceCents > 0) ...[
                      const SizedBox(width: 10),
                      Expanded(child: SizedBox(height: 48, child: buyButton)),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Använda gratis-intros: ${detail.freeConsumed}/${detail.freeLimit} $enrolledText',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (hasAccess && priceCents > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Du har redan full åtkomst till kursen.',
                    style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  if (hasSubscription && !isEnrolled)
                    Text(
                      'Din prenumeration ger dig åtkomst till allt innehåll.',
                      style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
                const SizedBox(height: 8),
                if (detail.latestOrder != null)
                  Row(
                    children: [
                      Text(
                        'Betalstatus: ${_orderStatusLabel(detail.latestOrder!.status)}',
                        style: t.bodySmall,
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => onRefreshOrderStatus(),
                        child: const Text('Uppdatera status'),
                      ),
                    ],
                  ),
                if (enrollError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _friendlyError(enrollError),
                      style: t.bodySmall?.copyWith(color: cs.error),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...detail.modules
              .where(
                (m) => m.title.isNotEmpty && !m.title.trim().startsWith('_'),
              )
              .map((module) {
                final lessons = (detail.lessonsByModule[module.id] ?? const [])
                    .where(
                      (l) =>
                          l.title.isNotEmpty && !l.title.trim().startsWith('_'),
                    )
                    .toList(growable: false);
                if (lessons.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassCard(
                    padding: const EdgeInsets.all(12),
                    opacity: 0.16,
                    borderRadius: BorderRadius.circular(22),
                    borderColor: Colors.white.withValues(alpha: 0.16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          module.title,
                          style: t.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...lessons.map((lesson) {
                          final isLocked = !lesson.isIntro && !hasAccess;
                          return ListTile(
                            leading: Icon(
                              isLocked
                                  ? Icons.lock_outline_rounded
                                  : Icons.play_circle_outline_rounded,
                            ),
                            title: Text(lesson.title),
                            subtitle: lesson.isIntro
                                ? const Text('Förhandsvisning')
                                : (isLocked
                                      ? const Text('Låst innehåll')
                                      : null),
                            enabled: !isLocked,
                            onTap: () => _handleLessonTap(
                              context,
                              lesson,
                              detail,
                              isLocked,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              }),
        ],
      ),
    );
  }

  void _openLesson(BuildContext context, String lessonId) {
    context.pushNamed(AppRoute.lesson, pathParameters: {'id': lessonId});
  }

  void _handleLessonTap(
    BuildContext context,
    LessonSummary lesson,
    CourseDetailData detail,
    bool isLocked,
  ) {
    if (!isLocked) {
      _openLesson(context, lesson.id);
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
