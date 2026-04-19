import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/payments/presentation/paywall_prompt.dart';
import 'package:aveli/shared/utils/course_cover_contract.dart';
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
        final courseCoverImageUrlFuture = Future<String?>.value(
          courseCoverResolvedUrl(detail.course.cover),
        );
        final courseStateAsync = ref.watch(
          courseStateProvider(detail.course.id),
        );
        return _CourseContent(
          detail: detail,
          courseStateAsync: courseStateAsync,
          courseCoverImageUrlFuture: courseCoverImageUrlFuture,
          onEnroll: () => _handleEnroll(detail),
          onOpenLesson: _openLesson,
          enrollState: ref.watch(enrollProvider(detail.course.id)),
          buyButton: null,
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
    required this.courseCoverImageUrlFuture,
    required this.onEnroll,
    required this.onOpenLesson,
    required this.enrollState,
    required this.buyButton,
  });

  final CourseDetailData detail;
  final AsyncValue<CourseAccessData?> courseStateAsync;
  final Future<String?> courseCoverImageUrlFuture;
  final VoidCallback onEnroll;
  final ValueChanged<String> onOpenLesson;
  final AsyncValue<CourseAccessData?> enrollState;
  final Widget? buyButton;

  @override
  Widget build(BuildContext context) {
    final course = detail.course;
    final teacherName = course.teacher?.displayName;
    final shortDescription = detail.shortDescription;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final courseState = courseStateAsync.valueOrNull;
    final hasEnrollment = courseState?.hasEnrollment == true;
    final currentUnlockPosition =
        courseState?.enrollment?.currentUnlockPosition;
    final canEnroll =
        !hasEnrollment &&
        (courseState?.enrollable == true || course.enrollable);
    final lessons = _visibleCourseLessons(detail.lessons);
    final unlockedLessons = lessons
        .where(
          (lesson) =>
              currentUnlockPosition != null &&
              lesson.position <= currentUnlockPosition,
        )
        .toList(growable: false);
    final isEnrolling = enrollState.isLoading;
    final enrollError = enrollState.whenOrNull(error: (error, _) => error);

    Widget? primaryCta;
    if (hasEnrollment && unlockedLessons.isNotEmpty) {
      primaryCta = FilledButton(
        onPressed: () => onOpenLesson(unlockedLessons.first.id),
        child: const Text('Fortsätt kursen'),
      );
    } else if (canEnroll) {
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
          FutureBuilder<String?>(
            future: courseCoverImageUrlFuture,
            builder: (context, snapshot) {
              final courseCoverImageUrl = snapshot.data;
              if (courseCoverImageUrl == null || courseCoverImageUrl.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Image.network(
                          courseCoverImageUrl,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
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
                  course.title,
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (teacherName != null) ...[
                  const SizedBox(height: 8),
                  Text('Lärare: $teacherName', style: t.bodyMedium),
                ],
                if (shortDescription != null) ...[
                  const SizedBox(height: 12),
                  Text(shortDescription, style: t.bodyLarge),
                ],
                const SizedBox(height: 12),
                if (primaryCta != null)
                  SizedBox(width: double.infinity, child: primaryCta),
                if (hasEnrollment && currentUnlockPosition != null) ...[
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
                          currentUnlockPosition == null ||
                          lesson.position > currentUnlockPosition;
                      return ListTile(
                        leading: Icon(
                          isLocked
                              ? Icons.lock_outline_rounded
                              : Icons.play_circle_outline_rounded,
                        ),
                        title: Text(lesson.lessonTitle),
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
            lesson.lessonTitle.isNotEmpty &&
            !lesson.lessonTitle.trim().startsWith('_'),
      )
      .toList(growable: false);
  visible.sort((a, b) => a.position.compareTo(b.position));
  return visible;
}
