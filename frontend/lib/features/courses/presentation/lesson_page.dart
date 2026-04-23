import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/editor/document/lesson_document.dart';
import 'package:aveli/editor/document/lesson_document_editor.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/learner_course_visibility.dart';
import 'package:aveli/shared/media/AveliLessonImage.dart';
import 'package:aveli/shared/media/AveliLessonMediaPlayer.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/background_layer.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/utils/lesson_media_render_telemetry.dart';

class LessonPage extends ConsumerStatefulWidget {
  const LessonPage({super.key, required this.lessonId});

  final String lessonId;

  @override
  ConsumerState<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends ConsumerState<LessonPage> {
  ProviderSubscription<AsyncValue<LessonDetailData>>? _lessonSub;

  @override
  void initState() {
    super.initState();
    _lessonSub = ref.listenManual<AsyncValue<LessonDetailData>>(
      lessonDetailProvider(widget.lessonId),
      (previous, next) {
        next.whenData(_updateProgress);
      },
    );
  }

  @override
  void dispose() {
    _lessonSub?.close();
    super.dispose();
  }

  Future<void> _updateProgress(LessonDetailData data) async {
    final courseId = data.courseId;
    final visibleLessons = visibleLearnerLessons(data.lessons);
    if (visibleLessons.isEmpty) return;
    final index = visibleLessons.indexWhere((l) => l.id == data.lesson.id);
    if (index < 0) return;
    final progress = (index + 1) / visibleLessons.length;
    final progressRepo = ref.read(progressRepositoryProvider);
    unawaited(progressRepo.setProgress(courseId, progress));
  }

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
      background: BackgroundLayer(
        image: AppImages.lessonBackground,
        imagePath: AppImages.lessonBackgroundPath,
      ),
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

LessonMediaItem? _findLessonMediaItem(
  Iterable<LessonMediaItem> lessonMedia,
  String? lessonMediaId, {
  required String expectedMediaType,
}) {
  final normalizedLessonMediaId = lessonMediaId?.trim() ?? '';
  if (normalizedLessonMediaId.isEmpty) {
    logMissingLessonMediaIdRender(
      surface: 'lesson_page_render',
      mediaType: expectedMediaType,
      rawSource: null,
    );
    return null;
  }
  for (final media in lessonMedia) {
    if (media.id != normalizedLessonMediaId) {
      continue;
    }
    if (media.mediaType != expectedMediaType) {
      logUnresolvedLessonMediaRender(
        event: 'UNRESOLVED_LESSON_MEDIA_RENDER',
        surface: 'lesson_page_render',
        mediaType: expectedMediaType,
        lessonMediaId: normalizedLessonMediaId,
        error: StateError('Lektionsmedia har fel typ.'),
      );
      return null;
    }
    return media;
  }
  logUnresolvedLessonMediaRender(
    event: 'UNRESOLVED_LESSON_MEDIA_RENDER',
    surface: 'lesson_page_render',
    mediaType: expectedMediaType,
    lessonMediaId: normalizedLessonMediaId,
    error: StateError('Lektionsmedia saknar backend-rad.'),
  );
  return null;
}

LessonDocumentPreviewMedia _previewMediaFromLessonMediaItem(
  LessonMediaItem item,
) {
  return LessonDocumentPreviewMedia(
    lessonMediaId: item.id,
    mediaType: item.mediaType,
    state: item.state,
    label: item.mediaAssetId,
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
        if (_readingMode == LessonDocumentReadingMode.glass)
          GlassCard(
            padding: const EdgeInsets.all(16),
            opacity: 0.16,
            sigmaX: 10,
            sigmaY: 10,
            borderRadius: BorderRadius.circular(22),
            borderColor: Colors.white.withValues(alpha: 0.16),
            child: renderer,
          )
        else
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
      mediaBuilder: (context, block, media) => _LearnerDocumentMediaBlock(
        block: block,
        media: media,
        lessonMedia: lessonMedia,
        onLaunchUrl: onLaunchUrl,
      ),
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

class _LessonGlassMediaWrapper extends StatelessWidget {
  const _LessonGlassMediaWrapper({required this.child});

  final Widget child;

  static const double _maxWidth = 860;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: GlassCard(
          padding: const EdgeInsets.all(8),
          borderRadius: BorderRadius.circular(16),
          borderColor: Colors.white.withValues(alpha: 0.16),
          child: child,
        ),
      ),
    );
  }
}

class _LessonMediaErrorState extends StatelessWidget {
  const _LessonMediaErrorState({
    required this.mediaType,
    required this.message,
  });

  final String mediaType;
  final String message;

  bool get _isImage => mediaType == 'image';
  bool get _isVideo => mediaType == 'video';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(height: 12),
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
    if (_isImage) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: content,
        ),
      );
    }
    if (_isVideo) {
      return AspectRatio(aspectRatio: 16 / 9, child: content);
    }
    return SizedBox(
      height: 160,
      child: Center(child: SingleChildScrollView(child: content)),
    );
  }
}

class _LearnerDocumentMediaBlock extends StatelessWidget {
  const _LearnerDocumentMediaBlock({
    required this.block,
    required this.media,
    required this.lessonMedia,
    this.onLaunchUrl,
  });

  final LessonMediaBlock block;
  final LessonDocumentPreviewMedia? media;
  final List<LessonMediaItem> lessonMedia;
  final ValueChanged<String>? onLaunchUrl;

  @override
  Widget build(BuildContext context) {
    final item = _findLessonMediaItem(
      lessonMedia,
      block.lessonMediaId,
      expectedMediaType: block.mediaType,
    );
    final resolved = media;
    final resolvedUrl = resolved?.resolvedUrl?.trim();
    if (item == null ||
        resolved == null ||
        resolved.mediaType != block.mediaType ||
        resolved.state != 'ready' ||
        resolvedUrl == null ||
        resolvedUrl.isEmpty) {
      return _LessonMediaErrorState(
        mediaType: block.mediaType,
        message: 'Lektionsmedia kunde inte laddas.',
      );
    }
    final label = _lessonMediaLabel(item, block.mediaType);
    switch (block.mediaType) {
      case 'image':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AveliLessonImage(src: resolvedUrl, alt: label),
        );
      case 'audio':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _LessonGlassMediaWrapper(
            child: AveliLessonMediaPlayer(
              mediaUrl: resolvedUrl,
              title: label,
              kind: block.mediaType,
              preferLessonLayout: true,
            ),
          ),
        );
      case 'video':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _LessonGlassMediaWrapper(
            child: AveliLessonMediaPlayer(
              mediaUrl: resolvedUrl,
              title: label,
              kind: block.mediaType,
              preferLessonLayout: true,
            ),
          ),
        );
      case 'document':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _LessonDownloadCard(
            fileName: label,
            onTap: () {
              final launchHandler = onLaunchUrl;
              if (launchHandler != null) {
                launchHandler(resolvedUrl);
                return;
              }
              unawaited(launchUrlString(resolvedUrl));
            },
          ),
        );
      default:
        return _LessonMediaErrorState(
          mediaType: block.mediaType,
          message: 'Lektionsmedia kunde inte laddas.',
        );
    }
  }

  String _lessonMediaLabel(LessonMediaItem item, String mediaType) {
    final mediaAssetId = item.mediaAssetId?.trim();
    if (mediaAssetId != null && mediaAssetId.isNotEmpty) {
      return mediaAssetId;
    }
    return switch (mediaType) {
      'image' => 'Bild',
      'audio' => 'Ljud',
      'video' => 'Video',
      'document' => 'Dokument',
      _ => 'Media',
    };
  }
}

class _LessonDownloadCard extends StatelessWidget {
  const _LessonDownloadCard({required this.fileName, required this.onTap});

  final String fileName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const label = 'Ladda ner dokument';
    const accent = Icons.description_outlined;

    return _LessonGlassMediaWrapper(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: br16,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: kBrandBluePurpleGradient,
                    borderRadius: br12,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(accent, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: kBrandBluePurpleGradient,
                    borderRadius: br12,
                    boxShadow: [
                      BoxShadow(
                        color: kBrandLilac.withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Icon(
                      Icons.download_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
