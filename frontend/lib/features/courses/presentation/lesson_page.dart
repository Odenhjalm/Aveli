import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/editor/document/lesson_document.dart';
import 'package:aveli/editor/document/lesson_document_renderer.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/learner_course_visibility.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/background_layer.dart';
import 'package:aveli/shared/widgets/glass_card.dart';

class LessonPage extends ConsumerStatefulWidget {
  const LessonPage({super.key, required this.lessonId});

  final String lessonId;

  @override
  ConsumerState<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends ConsumerState<LessonPage> {
  @override
  Widget build(BuildContext context) {
    final asyncLesson = ref.watch(lessonDetailProvider(widget.lessonId));
    return asyncLesson.when(
      loading: () => const AppScaffold(
        title: 'Lektion',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AppScaffold(
        title: 'Lektion',
        body: Center(
          child: Text(
            _lessonLoadErrorMessage(error),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (data) => _LessonContent(detail: data),
    );
  }
}

class _LessonContent extends ConsumerWidget {
  const _LessonContent({required this.detail});

  final LessonDetailData detail;

  Future<void> _handleLinkTap(BuildContext context, String url) async {
    final parsed = Uri.tryParse(url);
    if (parsed != null &&
        parsed.pathSegments.contains('pay') &&
        parsed.pathSegments.contains('bundle')) {
      _showLessonActionError(
        context,
        'Paketk\u00f6p \u00e4r inte tillg\u00e4ngligt i appen.',
      );
      return;
    }

    if (!await _tryLaunchExternal(url) && context.mounted) {
      _showLessonActionError(context, 'L\u00e4nken kunde inte \u00f6ppnas.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lesson = detail.lesson;
    final courseStateAsync = ref.watch(courseStateProvider(detail.courseId));
    final visibility = LearnerCourseVisibility.fromState(
      lessons: detail.lessons,
      courseState: courseStateAsync.valueOrNull,
      now: DateTime.now().toUtc(),
    );
    final screenWidth = MediaQuery.of(context).size.width;
    final safeScreenWidth = screenWidth.isFinite && screenWidth > 0
        ? screenWidth
        : 1200.0;
    final contentWidth = (safeScreenWidth - 32).clamp(720.0, 1200.0).toDouble();
    final courseLessons = visibility.lessons;
    LessonSummary? previous;
    LessonSummary? next;
    if (courseLessons.isNotEmpty) {
      final index = courseLessons.indexWhere(
        (element) => element.id == lesson.id,
      );
      if (index > 0) {
        previous = courseLessons[index - 1];
      }
      if (index >= 0 && index < courseLessons.length - 1) {
        next = courseLessons[index + 1];
      }
    }

    final documentContent = lesson.contentDocument;
    final hasLessonContent = documentContent.blocks.isNotEmpty;
    final coreContent = MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (hasLessonContent)
            LearnerLessonContentRenderer(
              document: documentContent,
              lessonMedia: detail.media,
              onLaunchUrl: (url) => unawaited(_handleLinkTap(context, url)),
            )
          else
            const _LessonEmptyContentState(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    final prev = previous;
                    if (prev == null) return;
                    context.goNamed(
                      AppRoute.lesson,
                      pathParameters: {'id': prev.id},
                    );
                  },
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('Föregående'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    final nxt = next;
                    if (nxt == null) return;
                    if (courseStateAsync.isLoading ||
                        courseStateAsync.hasError ||
                        courseStateAsync.valueOrNull == null) {
                      _showLessonActionError(
                        context,
                        'Kunde inte kontrollera nästa lektion just nu.',
                      );
                      return;
                    }
                    if (visibility.isLessonLocked(nxt)) {
                      _showLessonActionError(
                        context,
                        visibility.lockedLessonMessage(nxt),
                      );
                      return;
                    }
                    context.goNamed(
                      AppRoute.lesson,
                      pathParameters: {'id': nxt.id},
                    );
                  },
                  icon: Icon(
                    next != null && visibility.isLessonLocked(next)
                        ? Icons.lock_outline_rounded
                        : Icons.chevron_right_rounded,
                  ),
                  label: Text(
                    next != null && visibility.isLessonLocked(next)
                        ? 'Låst'
                        : 'Nästa',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return AppScaffold(
      title: lesson.lessonTitle,
      body: coreContent,
      background: const BackgroundLayer.lesson(),
      maxContentWidth: contentWidth,
    );
  }
}

String _lessonLoadErrorMessage(Object error) {
  if (error is AppFailure) {
    switch (error.kind) {
      case AppFailureKind.unauthorized:
        return 'Du har inte \u00e5tkomst till den h\u00e4r lektionen.';
      case AppFailureKind.notFound:
        return 'Lektionen kunde inte hittas.';
      case AppFailureKind.network:
      case AppFailureKind.timeout:
        return 'Lektionen kunde inte laddas. Kontrollera uppkopplingen och f\u00f6rs\u00f6k igen.';
      case AppFailureKind.server:
      case AppFailureKind.validation:
      case AppFailureKind.configuration:
      case AppFailureKind.unexpected:
        return 'Lektionen kunde inte laddas.';
    }
  }
  return 'Lektionen kunde inte laddas.';
}

Future<bool> _tryLaunchExternal(String url) async {
  try {
    return await launchUrlString(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

void _showLessonActionError(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class _LessonEmptyContentState extends StatelessWidget {
  const _LessonEmptyContentState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      opacity: 0.16,
      sigmaX: 10,
      sigmaY: 10,
      borderRadius: BorderRadius.circular(22),
      borderColor: Colors.white.withValues(alpha: 0.16),
      child: Text(
        'Lektionsinneh\u00e5llet saknas.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

LessonDocumentPreviewMedia _previewMediaFromLessonMediaItem(
  LessonMediaItem item,
) {
  return LessonDocumentPreviewMedia(
    lessonMediaId: item.id,
    mediaType: item.mediaType,
    state: item.state,
    label: null,
    resolvedUrl: item.media?.resolvedUrl,
  );
}

class LearnerLessonContentRenderer extends StatefulWidget {
  const LearnerLessonContentRenderer({
    super.key,
    required this.document,
    required this.lessonMedia,
    this.onLaunchUrl,
  });

  final LessonDocument document;
  final List<LessonMediaItem> lessonMedia;
  final ValueChanged<String>? onLaunchUrl;

  @override
  State<LearnerLessonContentRenderer> createState() =>
      _LearnerLessonContentRendererState();
}

class _LearnerLessonContentRendererState
    extends State<LearnerLessonContentRenderer> {
  LessonDocumentReadingMode _readingMode = LessonDocumentReadingMode.glass;

  @override
  Widget build(BuildContext context) {
    final renderer = LessonPageRenderer(
      document: widget.document,
      lessonMedia: widget.lessonMedia,
      onLaunchUrl: widget.onLaunchUrl,
      readingMode: _readingMode,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: LessonDocumentReadingModeToggle(
            value: _readingMode,
            onChanged: (mode) {
              if (mode == _readingMode) return;
              setState(() => _readingMode = mode);
            },
          ),
        ),
        const SizedBox(height: 12),
        renderer,
      ],
    );
  }
}

class LessonPageRenderer extends StatelessWidget {
  const LessonPageRenderer({
    super.key,
    required this.document,
    this.lessonMedia = const <LessonMediaItem>[],
    this.onLaunchUrl,
    this.readingMode = LessonDocumentReadingMode.glass,
  });

  final LessonDocument document;
  final List<LessonMediaItem> lessonMedia;
  final ValueChanged<String>? onLaunchUrl;
  final LessonDocumentReadingMode readingMode;

  @override
  Widget build(BuildContext context) {
    if (document.blocks.isEmpty) {
      return const _LessonRendererErrorState(
        message: 'Lektionsinnehållet saknas.',
      );
    }
    final previewMedia = lessonMedia
        .map(_previewMediaFromLessonMediaItem)
        .toList(growable: false);
    return LessonDocumentPreview(
      document: document,
      media: previewMedia,
      readingMode: readingMode,
      onLaunchUrl: onLaunchUrl ?? (url) => unawaited(_tryLaunchExternal(url)),
    );
  }
}

class _LessonRendererErrorState extends StatelessWidget {
  const _LessonRendererErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}
