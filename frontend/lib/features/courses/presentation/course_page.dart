import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/models/text_bundle.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/paywall/application/checkout_flow.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
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
  bool _ctaInFlight = false;

  @override
  Widget build(BuildContext context) {
    final asyncView = ref.watch(courseEntryViewProvider(widget.slug));
    return asyncView.when(
      loading: () => const AppScaffold(
        title: '',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AppScaffold(
        title: '',
        body: Center(
          child: Text(
            _courseLoadErrorMessage(error),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (view) => _CourseContent(
        view: view,
        ctaBusy: _ctaInFlight,
        onPrimaryCta: view.cta.enabled && view.cta.action != null
            ? () => _handlePrimaryCta(view)
            : null,
        onOpenLesson: _openLesson,
      ),
    );
  }

  Future<void> _handlePrimaryCta(CourseEntryViewData view) async {
    if (_ctaInFlight || !view.cta.enabled) {
      return;
    }
    switch (view.cta.actionType) {
      case 'lesson':
        final lessonId = _stringActionValue(view.cta.action, 'lesson_id');
        if (lessonId != null) {
          _openLesson(lessonId);
        }
        return;
      case 'enroll':
        await _enroll(view);
        return;
      case 'checkout':
        await _startCheckout(view);
        return;
    }

    final message = view.cta.reasonText;
    if (message != null && message.isNotEmpty && mounted && context.mounted) {
      showSnack(context, message);
    }
  }

  Future<void> _enroll(CourseEntryViewData view) async {
    setState(() => _ctaInFlight = true);
    try {
      await ref.read(coursesRepositoryProvider).enrollCourse(view.course.id);
      ref.invalidate(courseEntryViewProvider(widget.slug));
      ref.invalidate(myCoursesProvider);
      if (!mounted || !context.mounted) return;
      showSnack(context, 'Du \u00e4r nu anm\u00e4ld till kursen.');
    } catch (error, stackTrace) {
      if (!mounted || !context.mounted) return;
      final failure = AppFailure.from(error, stackTrace);
      showSnack(context, failure.message);
    } finally {
      if (mounted) {
        setState(() => _ctaInFlight = false);
      }
    }
  }

  Future<void> _startCheckout(CourseEntryViewData view) async {
    setState(() => _ctaInFlight = true);
    try {
      final launch = await ref
          .read(checkoutApiProvider)
          .createCourseCheckout(slug: view.course.slug);
      ref.read(checkoutContextProvider.notifier).state = CheckoutContext(
        type: CheckoutItemType.course,
        courseSlug: view.course.slug,
        courseTitle: view.course.title,
        returnPath: _currentRoute(),
      );
      ref
          .read(checkoutRedirectStateProvider.notifier)
          .state = CheckoutRedirectState(
        status: CheckoutRedirectStatus.processing,
        sessionId: launch.sessionId,
        orderId: launch.orderId,
      );
      if (!mounted || !context.mounted) return;
      context.pushNamed(AppRoute.checkout, extra: launch.url);
    } catch (error, stackTrace) {
      if (!mounted || !context.mounted) return;
      final failure = AppFailure.from(error, stackTrace);
      showSnack(context, failure.message);
    } finally {
      if (mounted) {
        setState(() => _ctaInFlight = false);
      }
    }
  }

  void _openLesson(String lessonId) {
    if (!mounted || !context.mounted) return;
    context.pushNamed(AppRoute.lesson, pathParameters: {'id': lessonId});
  }

  String _currentRoute() {
    try {
      return GoRouterState.of(context).uri.toString();
    } catch (_) {
      return '/';
    }
  }
}

String? _stringActionValue(Map<String, Object?>? action, String key) {
  final value = action?[key];
  return value is String && value.isNotEmpty ? value : null;
}

String _courseLoadErrorMessage(Object error) {
  final failure = AppFailure.from(error);
  switch (failure.kind) {
    case AppFailureKind.notFound:
      return 'Kursen kunde inte hittas.';
    case AppFailureKind.unauthorized:
      return 'Du har inte \u00e5tkomst till den h\u00e4r kursen.';
    case AppFailureKind.network:
    case AppFailureKind.timeout:
      return 'Kursen kunde inte laddas. Kontrollera uppkopplingen och f\u00f6rs\u00f6k igen.';
    case AppFailureKind.server:
    case AppFailureKind.validation:
    case AppFailureKind.configuration:
    case AppFailureKind.unexpected:
      return 'Kursen kunde inte laddas.';
  }
}

class _CourseContent extends StatelessWidget {
  const _CourseContent({
    required this.view,
    required this.ctaBusy,
    required this.onPrimaryCta,
    required this.onOpenLesson,
  });

  final CourseEntryViewData view;
  final bool ctaBusy;
  final VoidCallback? onPrimaryCta;
  final ValueChanged<String> onOpenLesson;

  @override
  Widget build(BuildContext context) {
    final course = view.course;
    final description = course.description;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final cover = course.cover;
    final priceLabel = _backendPriceLabel(view);
    final ctaText = _resolveCatalogText(view.cta.textId, view.textBundles);
    final ctaReason = view.cta.reasonText;
    final title = course.title.isEmpty
        ? _resolveCatalogText(
                'course_lesson.course.title_fallback',
                view.textBundles,
              ) ??
              ''
        : course.title;
    final dripReleaseNotice = view.access.isInDrip
        ? _resolveCatalogText(
            'course_lesson.course.drip_release_notice',
            view.textBundles,
          )
        : null;

    return AppScaffold(
      title: title,
      body: ListView(
        children: [
          if (cover != null && cover.url.isNotEmpty)
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Image.network(
                        cover.url,
                        fit: BoxFit.contain,
                        semanticLabel: cover.alt,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          GlassCard(
            padding: const EdgeInsets.all(20),
            opacity: 0.18,
            borderRadius: BorderRadius.circular(26),
            borderColor: Colors.white.withValues(alpha: 0.18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(description, style: t.bodyLarge),
                ],
                if (priceLabel != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    priceLabel,
                    style: t.titleMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: ctaBusy || ctaText == null ? null : onPrimaryCta,
                    child: ctaBusy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : ctaText == null
                        ? const SizedBox.shrink()
                        : Text(ctaText),
                  ),
                ),
                if (ctaReason != null && ctaReason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    ctaReason,
                    style: t.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (dripReleaseNotice != null) ...[
                  const SizedBox(height: 8),
                  _CourseStatusLine(
                    icon: Icons.schedule_rounded,
                    text: dripReleaseNotice,
                    style: t.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (view.lessons.isNotEmpty)
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
                    ...view.lessons.map(
                      (entryLesson) => _EntryLessonTile(
                        entryLesson: entryLesson,
                        onOpenLesson: onOpenLesson,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryLessonTile extends StatelessWidget {
  const _EntryLessonTile({
    required this.entryLesson,
    required this.onOpenLesson,
  });

  final CourseEntryLessonShellData entryLesson;
  final ValueChanged<String> onOpenLesson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final locked = entryLesson.availability.state == 'locked';
    final status = _lessonStatusLabel(entryLesson);

    return Opacity(
      opacity: locked ? 0.58 : 1,
      child: ListTile(
        leading: Icon(
          locked
              ? Icons.lock_outline_rounded
              : Icons.play_circle_outline_rounded,
          color: locked ? cs.onSurfaceVariant : cs.primary,
        ),
        title: Text(
          entryLesson.lessonTitle,
          style: locked
              ? theme.textTheme.titleMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                )
              : null,
        ),
        subtitle: status == null
            ? null
            : Text(
                status,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: locked ? cs.onSurfaceVariant : cs.onSurface,
                ),
              ),
        onTap: () {
          if (entryLesson.availability.canOpen) {
            onOpenLesson(entryLesson.id);
            return;
          }
          final message = entryLesson.availability.reasonText;
          if (message != null && message.isNotEmpty) {
            showSnack(context, message);
          }
        },
      ),
    );
  }
}

String? _backendPriceLabel(CourseEntryViewData view) {
  final pricingPrice = view.pricing?.formattedPrice;
  if (pricingPrice != null && pricingPrice.isNotEmpty) {
    return pricingPrice;
  }
  final coursePrice = view.course.formattedPrice;
  return coursePrice != null && coursePrice.isNotEmpty ? coursePrice : null;
}

String? _resolveCatalogText(String textId, List<TextBundle> textBundles) {
  try {
    return resolveText(textId, textBundles);
  } catch (_) {
    return null;
  }
}

String? _lessonStatusLabel(CourseEntryLessonShellData entryLesson) {
  final reasonText = entryLesson.availability.reasonText;
  if (reasonText != null && reasonText.isNotEmpty) {
    return reasonText;
  }
  final availabilityState = entryLesson.availability.state;
  if (availabilityState == 'locked') {
    return 'L\u00e5st';
  }
  return null;
}

class _CourseStatusLine extends StatelessWidget {
  const _CourseStatusLine({required this.icon, required this.text, this.style});

  final IconData icon;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}
