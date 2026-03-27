import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/editor/adapter/markdown_to_editor.dart'
    as markdown_to_editor;
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_access_gate.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/shared/media/AveliLessonImage.dart';
import 'package:aveli/shared/media/AveliLessonMediaPlayer.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/background_layer.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/utils/lesson_content_pipeline.dart';
import 'package:aveli/shared/utils/lesson_media_render_telemetry.dart';
import 'package:aveli/shared/utils/lesson_media_playback_resolver.dart';

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
    final visibleLessons = _visibleCourseLessons(data.lessons);
    if (courseId == null || visibleLessons.isEmpty) return;
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
        body: Center(child: Text(_friendlyError(error))),
      ),
      data: (data) => _LessonContent(detail: data),
    );
  }

  String _friendlyError(Object error) {
    if (error is AppFailure) return error.message;
    return 'Kunde inte ladda lektionen.';
  }
}

class _LessonContent extends ConsumerWidget {
  const _LessonContent({required this.detail});

  final LessonDetailData detail;

  String _normalizeMarkdown(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Inget innehåll.';
    }
    return value;
  }

  List<_BundleLink> _extractBundleLinks(String content) {
    final regex = RegExp(r'https?://[^\s)]+/pay/bundle/([A-Za-z0-9-]+)');
    return regex
        .allMatches(content)
        .map((match) {
          final matchedUrl = match.group(0);
          final bundleId = match.group(1) ?? '';
          if (matchedUrl == null || matchedUrl.trim().isEmpty) {
            return null;
          }
          return _BundleLink(url: matchedUrl.trim(), bundleId: bundleId.trim());
        })
        .whereType<_BundleLink>()
        .where((item) => item.bundleId.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _startBundleCheckout(
    BuildContext context,
    WidgetRef ref,
    String bundleId,
  ) async {
    try {
      final checkoutApi = ref.read(checkoutApiProvider);
      final checkoutUrl = await checkoutApi.startBundleCheckout(
        bundleId: bundleId,
      );
      if (context.mounted) {
        context.push(RoutePath.checkout, extra: checkoutUrl);
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(context, 'Kunde inte öppna paketbetalning: $e');
      }
    }
  }

  Future<void> _handleLinkTap(
    BuildContext context,
    WidgetRef ref,
    String url,
  ) async {
    final parsed = Uri.tryParse(url);
    if (parsed != null &&
        parsed.pathSegments.contains('pay') &&
        parsed.pathSegments.contains('bundle')) {
      final bundleId = parsed.pathSegments.isNotEmpty
          ? parsed.pathSegments.last
          : parsed.queryParameters['bundle_id'];
      if (bundleId != null && bundleId.isNotEmpty) {
        await _startBundleCheckout(context, ref, bundleId);
        return;
      }
    }

    final lessonMediaId = lessonMediaIdFromDocumentLinkUrl(url)?.trim();
    if (lessonMediaId != null && lessonMediaId.isNotEmpty) {
      final mediaRepo = ref.read(mediaRepositoryProvider);
      final pipelineRepo = ref.read(mediaPipelineRepositoryProvider);
      try {
        final resolvedUrl = await resolveLessonMediaSignedPlaybackUrl(
          lessonMediaId: lessonMediaId,
          mediaRepository: mediaRepo,
          pipelineRepository: pipelineRepo,
        );
        if (resolvedUrl == null) {
          logUnresolvedLessonMediaRender(
            event: 'UNRESOLVED_LESSON_MEDIA_RENDER',
            surface: 'lesson_page_link',
            mediaType: 'document',
            lessonMediaId: lessonMediaId,
          );
          if (context.mounted) {
            showSnack(context, 'Dokumentet kunde inte öppnas.');
          }
          return;
        }
        if (!await launchUrlString(
          resolvedUrl,
          mode: LaunchMode.externalApplication,
        )) {
          if (context.mounted) {
            showSnack(context, 'Kunde inte öppna länken.');
          }
        }
        return;
      } catch (error) {
        logUnresolvedLessonMediaRender(
          event: 'UNRESOLVED_LESSON_MEDIA_RENDER',
          surface: 'lesson_page_link',
          mediaType: 'document',
          lessonMediaId: lessonMediaId,
          error: error,
        );
        if (context.mounted) {
          showSnack(context, 'Dokumentet kunde inte öppnas.');
        }
        return;
      }
    }

    final parsedPath = parsed?.path ?? url;
    if (_isAuthProtectedLessonMediaPath(parsedPath)) {
      logLegacyMediaBlocked(
        surface: 'lesson_page_link',
        mediaType: 'document',
        rawSource: url,
        reason: 'legacy_path',
      );
      if (context.mounted) {
        showSnack(context, 'Kunde inte öppna medielänken.');
      }
      return;
    }

    if (!await launchUrlString(url, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        showSnack(context, 'Kunde inte öppna länken.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lesson = detail.lesson;
    final screenWidth = MediaQuery.of(context).size.width;
    final safeScreenWidth = screenWidth.isFinite && screenWidth > 0
        ? screenWidth
        : 1200.0;
    final contentWidth = (safeScreenWidth - 32).clamp(720.0, 1200.0).toDouble();
    final mediaItems = detail.media;
    final courseLessons = _visibleCourseLessons(detail.lessons);
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

    final markdownContent = _normalizeMarkdown(lesson.contentMarkdown);
    final bundleLinks = _extractBundleLinks(markdownContent);
    final embeddedMediaIds = extractLessonEmbeddedMediaIds(markdownContent);

    bool isEmbedded(LessonMediaItem item) {
      final mediaId = item.mediaId;
      if (mediaId != null && embeddedMediaIds.contains(mediaId)) return true;
      if (embeddedMediaIds.contains(item.id)) return true;
      return false;
    }

    final trailingMedia = mediaItems
        .where((item) => !isEmbedded(item))
        .where(_isAllowedTrailingLessonMediaType)
        .toList(growable: false);

    final coreContent = MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(16),
            opacity: 0.16,
            sigmaX: 10,
            sigmaY: 10,
            borderRadius: BorderRadius.circular(22),
            borderColor: Colors.white.withValues(alpha: 0.16),
            child: LessonPageRenderer(
              markdown: markdownContent,
              lessonMedia: mediaItems,
              onLaunchUrl: (url) =>
                  unawaited(_handleLinkTap(context, ref, url)),
            ),
          ),
          if (bundleLinks.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...bundleLinks.map(
              (link) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: FilledButton.icon(
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Köp paketet'),
                  onPressed: () =>
                      _startBundleCheckout(context, ref, link.bundleId),
                ),
              ),
            ),
          ],
          if (trailingMedia.isNotEmpty) ...[
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(12),
              borderRadius: BorderRadius.circular(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...trailingMedia.map((item) => _MediaItem(item: item)),
                ],
              ),
            ),
          ],
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
                    context.goNamed(
                      AppRoute.lesson,
                      pathParameters: {'id': nxt.id},
                    );
                  },
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('Nästa'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final courseId = detail.courseId;
    final gatedContent = (!lesson.isIntro && courseId != null)
        ? CourseAccessGate(courseId: courseId, child: coreContent)
        : coreContent;

    return AppScaffold(
      title: lesson.title.trim().isEmpty ? 'Lektion' : lesson.title,
      body: gatedContent,
      background: BackgroundLayer(
        image: AppImages.lessonBackground,
        imagePath: AppImages.lessonBackgroundPath,
      ),
      maxContentWidth: contentWidth,
    );
  }
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

class _BundleLink {
  const _BundleLink({required this.url, required this.bundleId});
  final String url;
  final String bundleId;
}

const bool _hideUnavailableTrailingMedia = false;
const Set<String> _allowedTrailingLessonMediaKinds = {'document', 'pdf'};

bool _isAllowedTrailingLessonMediaType(LessonMediaItem item) {
  final normalizedKind = item.kind.trim().toLowerCase();
  if (_allowedTrailingLessonMediaKinds.contains(normalizedKind)) return true;
  return isLessonMediaPdf(item);
}

class LessonPageRenderer extends ConsumerStatefulWidget {
  const LessonPageRenderer({
    super.key,
    required this.markdown,
    this.lessonMedia = const <LessonMediaItem>[],
    this.emptyText = 'Inget innehåll.',
    this.onLaunchUrl,
  });

  final String markdown;
  final List<LessonMediaItem> lessonMedia;
  final String emptyText;
  final ValueChanged<String>? onLaunchUrl;

  @override
  ConsumerState<LessonPageRenderer> createState() => _LessonPageRendererState();
}

class _LessonPageRendererState extends ConsumerState<LessonPageRenderer> {
  late Future<String> _preparedMarkdownFuture;
  late String _normalizedMarkdown;
  late String _lessonMediaSignature;

  @override
  void initState() {
    super.initState();
    _normalizedMarkdown = _normalizeMarkdown(widget.markdown, widget.emptyText);
    _lessonMediaSignature = _buildLessonMediaSignature(widget.lessonMedia);
    _preparedMarkdownFuture = _createPreparedMarkdownFuture();
  }

  @override
  void didUpdateWidget(covariant LessonPageRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextMarkdown = _normalizeMarkdown(widget.markdown, widget.emptyText);
    final nextSignature = _buildLessonMediaSignature(widget.lessonMedia);
    if (_normalizedMarkdown == nextMarkdown &&
        _lessonMediaSignature == nextSignature) {
      return;
    }
    _normalizedMarkdown = nextMarkdown;
    _lessonMediaSignature = nextSignature;
    _preparedMarkdownFuture = _createPreparedMarkdownFuture();
  }

  Future<String> _createPreparedMarkdownFuture() {
    final mediaRepo = ref.read(mediaRepositoryProvider);
    final pipelineRepo = ref.read(mediaPipelineRepositoryProvider);
    return prepareLessonMarkdownForRendering(
      mediaRepo,
      _normalizedMarkdown,
      lessonMedia: widget.lessonMedia,
      pipelineRepository: pipelineRepo,
    );
  }

  void _retryPreparedMarkdown() {
    setState(() {
      _preparedMarkdownFuture = _createPreparedMarkdownFuture();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _preparedMarkdownFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return _LessonRendererErrorState(onRetry: _retryPreparedMarkdown);
        }

        final prepared = (snapshot.data ?? _normalizedMarkdown).trim();
        return _LessonQuillContent(
          markdown: prepared.isEmpty ? widget.emptyText : prepared,
          onLaunchUrl:
              widget.onLaunchUrl ?? (url) => unawaited(launchUrlString(url)),
        );
      },
    );
  }
}

String _normalizeMarkdown(String markdown, String emptyText) {
  if (markdown.trim().isEmpty) {
    return emptyText;
  }
  return markdown;
}

String _buildLessonMediaSignature(Iterable<LessonMediaItem> items) {
  final buffer = StringBuffer();
  for (final item in items) {
    buffer
      ..write(item.id)
      ..write('|')
      ..write(item.kind)
      ..write('|')
      ..write(item.originalName ?? '')
      ..write('|')
      ..write(item.mediaState ?? '')
      ..write(';');
  }
  return buffer.toString();
}

class _LessonRendererErrorState extends StatelessWidget {
  const _LessonRendererErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Kunde inte rendera lektionsinnehållet.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Försök igen'),
          ),
        ],
      ),
    );
  }
}

class _LessonQuillContent extends StatefulWidget {
  const _LessonQuillContent({
    required this.markdown,
    required this.onLaunchUrl,
  });

  final String markdown;
  final ValueChanged<String> onLaunchUrl;

  @override
  State<_LessonQuillContent> createState() => _LessonQuillContentState();
}

class _LessonQuillContentState extends State<_LessonQuillContent> {
  late quill.QuillController _controller;
  late String _markdown;

  @override
  void initState() {
    super.initState();
    _markdown = widget.markdown;
    _controller = _buildController(_markdown);
  }

  @override
  void didUpdateWidget(covariant _LessonQuillContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.markdown == _markdown) return;
    _controller.dispose();
    _markdown = widget.markdown;
    _controller = _buildController(_markdown);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  quill.QuillController _buildController(String markdown) {
    try {
      final document = markdown_to_editor.markdownToEditorDocument(
        markdown: markdown,
      );
      return quill.QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
    } catch (_) {
      final document = quill.Document()
        ..insert(0, 'Kunde inte rendera lektionsinnehållet.');
      return quill.QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultEmbedBuilders = FlutterQuillEmbeds.editorBuilders(
      videoEmbedConfig: null,
    );
    final embedBuilders = <quill.EmbedBuilder>[
      const _LessonVideoEmbedBuilder(),
      const _LessonAudioEmbedBuilder(),
      const _LessonImageEmbedBuilder(),
      ...defaultEmbedBuilders.where(
        (builder) =>
            builder.key != quill.BlockEmbed.imageType &&
            builder.key != quill.BlockEmbed.videoType &&
            builder.key != AudioBlockEmbed.embedType,
      ),
    ];

    try {
      return quill.QuillEditor.basic(
        controller: _controller,
        config: quill.QuillEditorConfig(
          scrollable: false,
          padding: EdgeInsets.zero,
          enableInteractiveSelection: false,
          enableSelectionToolbar: false,
          showCursor: false,
          readOnlyMouseCursor: SystemMouseCursors.basic,
          onLaunchUrl: widget.onLaunchUrl,
          embedBuilders: embedBuilders,
        ),
      );
    } catch (_) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Kunde inte rendera lektionsinnehållet.'),
      );
    }
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

class _LegacyLessonVideoFallback extends StatelessWidget {
  const _LegacyLessonVideoFallback();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Den här lektionen innehåller äldre videoformat.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _LessonResolvedMediaBuilder =
    Widget Function(BuildContext context, String resolvedUrl);

typedef _LessonResolvedMediaPlaceholderBuilder =
    Widget Function(
      BuildContext context, {
      required bool isLoading,
      required _LessonMediaResolveFailureState failureState,
      required VoidCallback onRetry,
    });

enum _LessonMediaResolveFailureState { missingId, legacyBlocked, unresolved }

class _LessonResolvedMedia extends ConsumerStatefulWidget {
  const _LessonResolvedMedia({
    required this.initialUrl,
    required this.lessonMediaId,
    required this.mediaType,
    required this.builder,
    required this.placeholderBuilder,
  });

  final String initialUrl;
  final String? lessonMediaId;
  final String mediaType;
  final _LessonResolvedMediaBuilder builder;
  final _LessonResolvedMediaPlaceholderBuilder placeholderBuilder;

  @override
  ConsumerState<_LessonResolvedMedia> createState() =>
      _LessonResolvedMediaState();
}

class _LessonResolvedMediaState extends ConsumerState<_LessonResolvedMedia> {
  late Future<String?> _resolvedUrlFuture;
  bool _loggedUnresolvedRender = false;
  _LessonMediaResolveFailureState _failureState =
      _LessonMediaResolveFailureState.unresolved;

  @override
  void initState() {
    super.initState();
    _resolvedUrlFuture = _createResolvedUrlFuture();
  }

  @override
  void didUpdateWidget(covariant _LessonResolvedMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUrl = oldWidget.initialUrl.trim();
    final nextUrl = widget.initialUrl.trim();
    final oldMediaId = oldWidget.lessonMediaId?.trim() ?? '';
    final nextMediaId = widget.lessonMediaId?.trim() ?? '';
    final oldType = oldWidget.mediaType.trim();
    final nextType = widget.mediaType.trim();
    if (oldUrl == nextUrl && oldMediaId == nextMediaId && oldType == nextType) {
      return;
    }
    _resolvedUrlFuture = _createResolvedUrlFuture();
  }

  Future<String?> _createResolvedUrlFuture() {
    final lessonMediaId = widget.lessonMediaId?.trim() ?? '';
    if (lessonMediaId.isEmpty) {
      final rawSource = widget.initialUrl.trim();
      _failureState = rawSource.isNotEmpty
          ? _LessonMediaResolveFailureState.legacyBlocked
          : _LessonMediaResolveFailureState.missingId;
      logMissingLessonMediaIdRender(
        surface: 'lesson_page_render',
        mediaType: widget.mediaType,
        rawSource: rawSource,
      );
      if (rawSource.isNotEmpty) {
        logLegacyMediaBlocked(
          surface: 'lesson_page_render',
          mediaType: widget.mediaType,
          rawSource: rawSource,
          reason: _isAuthProtectedLessonMediaPath(rawSource)
              ? 'legacy_path'
              : 'raw_media_url',
        );
      }
      return SynchronousFuture<String?>(null);
    }

    _failureState = _LessonMediaResolveFailureState.unresolved;
    final mediaRepo = ref.read(mediaRepositoryProvider);
    final pipelineRepo = ref.read(mediaPipelineRepositoryProvider);
    return resolveLessonMediaSignedPlaybackUrl(
      lessonMediaId: lessonMediaId,
      mediaRepository: mediaRepo,
      pipelineRepository: pipelineRepo,
    ).catchError((error) {
      logUnresolvedLessonMediaRender(
        event: 'UNRESOLVED_LESSON_MEDIA_RENDER',
        surface: 'lesson_page_render',
        mediaType: widget.mediaType,
        lessonMediaId: lessonMediaId,
        error: error,
      );
      return null;
    });
  }

  void _retry() {
    setState(() {
      _resolvedUrlFuture = _createResolvedUrlFuture();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _resolvedUrlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.placeholderBuilder(
            context,
            isLoading: true,
            failureState: _failureState,
            onRetry: _retry,
          );
        }

        final resolvedUrl = _normalizeResolvedLessonMediaUrl(snapshot.data);
        if (resolvedUrl == null) {
          final lessonMediaId = widget.lessonMediaId?.trim();
          if (!_loggedUnresolvedRender &&
              lessonMediaId != null &&
              lessonMediaId.isNotEmpty) {
            _loggedUnresolvedRender = true;
            logUnresolvedLessonMediaRender(
              event: 'UNRESOLVED_LESSON_MEDIA_RENDER',
              surface: 'lesson_page_render',
              mediaType: widget.mediaType,
              lessonMediaId: lessonMediaId,
            );
          }
          return widget.placeholderBuilder(
            context,
            isLoading: false,
            failureState: _failureState,
            onRetry: _retry,
          );
        }

        _loggedUnresolvedRender = false;
        return widget.builder(context, resolvedUrl);
      },
    );
  }
}

String? _normalizeResolvedLessonMediaUrl(String? rawValue) {
  final trimmed = rawValue?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  if (_isAuthProtectedLessonMediaPath(uri.path)) return null;
  return uri.toString();
}

bool _isAuthProtectedLessonMediaPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  final normalized = (uri?.path ?? trimmed).trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return normalized.startsWith('/studio/media/') ||
      normalized.startsWith('/api/media/') ||
      normalized.startsWith('/media/sign') ||
      normalized.startsWith('/media/stream/');
}

class _LessonMediaResolvePlaceholder extends StatelessWidget {
  const _LessonMediaResolvePlaceholder({
    required this.mediaType,
    required this.isLoading,
    required this.failureState,
    required this.onRetry,
  });

  final String mediaType;
  final bool isLoading;
  final _LessonMediaResolveFailureState failureState;
  final VoidCallback onRetry;

  bool get _isVideo => mediaType == 'video';
  bool get _isImage => mediaType == 'image';

  IconData _iconForType() {
    switch (mediaType) {
      case 'image':
        return Icons.image_outlined;
      case 'audio':
        return Icons.audiotrack_outlined;
      case 'video':
        return Icons.movie_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _messageText() {
    if (isLoading) {
      switch (mediaType) {
        case 'image':
          return 'Laddar bild...';
        case 'audio':
          return 'Laddar ljud...';
        case 'video':
          return 'Laddar video...';
        default:
          return 'Laddar media...';
      }
    }
    if (failureState == _LessonMediaResolveFailureState.missingId) {
      return 'Media saknar ID och kan inte visas';
    }
    if (failureState == _LessonMediaResolveFailureState.legacyBlocked) {
      return 'Äldre media blockerat';
    }
    switch (mediaType) {
      case 'image':
        return 'Bilden kunde inte laddas';
      case 'audio':
      case 'video':
        return 'Media saknas eller kunde inte lösas';
      default:
        return 'Mediet kunde inte laddas';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            )
          else
            Icon(_iconForType(), color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            _messageText(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isLoading
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (!isLoading &&
              failureState == _LessonMediaResolveFailureState.unresolved) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Försök igen'),
            ),
          ],
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
      height: isLoading ? 96 : 160,
      child: Center(child: SingleChildScrollView(child: content)),
    );
  }
}

class _LessonImageEmbedBuilder implements quill.EmbedBuilder {
  const _LessonImageEmbedBuilder();

  @override
  String get key => quill.BlockEmbed.imageType;

  @override
  bool get expanded => false;

  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(child: widget);

  @override
  String toPlainText(quill.Embed node) =>
      quill.Embed.kObjectReplacementCharacter;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final dynamic value = embedContext.node.value.data;
    final lessonMediaId = lessonMediaIdFromEmbedValue(value);
    final src = rawLessonMediaSourceFromEmbedValue(value) ?? '';
    final alt = lessonMediaAltFromEmbedValue(value);
    return _LessonResolvedMedia(
      initialUrl: src,
      lessonMediaId: lessonMediaId,
      mediaType: 'image',
      builder: (context, resolvedUrl) =>
          AveliLessonImage(src: resolvedUrl, alt: alt),
      placeholderBuilder:
          (
            context, {
            required isLoading,
            required failureState,
            required onRetry,
          }) => _LessonMediaResolvePlaceholder(
            mediaType: 'image',
            isLoading: isLoading,
            failureState: failureState,
            onRetry: onRetry,
          ),
    );
  }
}

class _LessonResolvedAudioPlayer extends StatelessWidget {
  const _LessonResolvedAudioPlayer({
    required this.url,
    required this.lessonMediaId,
  });

  final String url;
  final String? lessonMediaId;

  @override
  Widget build(BuildContext context) {
    return _LessonResolvedMedia(
      initialUrl: url,
      lessonMediaId: lessonMediaId,
      mediaType: 'audio',
      builder: (context, resolvedUrl) => AveliLessonMediaPlayer(
        playbackUrl: resolvedUrl,
        title: 'Ljud',
        kind: 'audio',
        preferLessonLayout: true,
      ),
      placeholderBuilder:
          (
            context, {
            required isLoading,
            required failureState,
            required onRetry,
          }) => _LessonMediaResolvePlaceholder(
            mediaType: 'audio',
            isLoading: isLoading,
            failureState: failureState,
            onRetry: onRetry,
          ),
    );
  }
}

class _LessonResolvedVideoPlayer extends StatelessWidget {
  const _LessonResolvedVideoPlayer({required this.url, this.lessonMediaId});

  final String url;
  final String? lessonMediaId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _LessonGlassMediaWrapper(
        child: _LessonResolvedMedia(
          initialUrl: url,
          lessonMediaId: lessonMediaId,
          mediaType: 'video',
          builder: (context, resolvedUrl) => AveliLessonMediaPlayer(
            playbackUrl: resolvedUrl,
            title: 'Video',
            kind: 'video',
            preferLessonLayout: true,
          ),
          placeholderBuilder:
              (
                context, {
                required isLoading,
                required failureState,
                required onRetry,
              }) => _LessonMediaResolvePlaceholder(
                mediaType: 'video',
                isLoading: isLoading,
                failureState: failureState,
                onRetry: onRetry,
              ),
        ),
      ),
    );
  }
}

class _LessonAudioEmbedBuilder implements quill.EmbedBuilder {
  const _LessonAudioEmbedBuilder();

  @override
  String get key => AudioBlockEmbed.embedType;

  @override
  bool get expanded => true;

  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(child: widget);

  @override
  String toPlainText(quill.Embed node) =>
      quill.Embed.kObjectReplacementCharacter;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final dynamic value = embedContext.node.value.data;
    final lessonMediaId = lessonMediaIdFromEmbedValue(value);
    final url = rawLessonMediaSourceFromEmbedValue(value) ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _LessonGlassMediaWrapper(
        child: _LessonResolvedAudioPlayer(
          url: url.trim(),
          lessonMediaId: lessonMediaId,
        ),
      ),
    );
  }
}

class _LessonVideoEmbedBuilder implements quill.EmbedBuilder {
  const _LessonVideoEmbedBuilder();

  @override
  String get key => quill.BlockEmbed.videoType;

  @override
  bool get expanded => true;

  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(child: widget);

  @override
  String toPlainText(quill.Embed node) =>
      quill.Embed.kObjectReplacementCharacter;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final dynamic value = embedContext.node.value.data;
    if (isLegacyVideoEmbed(value)) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: _LessonGlassMediaWrapper(child: _LegacyLessonVideoFallback()),
      );
    }
    final lessonMediaId = lessonMediaIdFromEmbedValue(value);
    final url = rawLessonMediaSourceFromEmbedValue(value) ?? '';
    return _LessonResolvedVideoPlayer(
      url: url.trim(),
      lessonMediaId: lessonMediaId,
    );
  }
}

class _MediaItem extends ConsumerWidget {
  const _MediaItem({required this.item});

  final LessonMediaItem item;

  String get _fileName => item.fileName;

  IconData _iconForKind() {
    switch (item.kind) {
      case 'image':
        return Icons.image_outlined;
      case 'video':
        return Icons.movie_creation_outlined;
      case 'audio':
        return Icons.audiotrack_outlined;
      case 'document':
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Widget _buildUnavailableMediaTile() {
    if (_hideUnavailableTrailingMedia) {
      return const SizedBox.shrink();
    }
    return ListTile(
      leading: Icon(_iconForKind()),
      title: Text(_fileName),
      subtitle: const Text('Otillgängligt media'),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalizedLessonMediaId = item.id.trim();
    if (normalizedLessonMediaId.isEmpty) {
      logMissingLessonMediaIdRender(
        surface: 'lesson_page_trailing_media',
        mediaType: item.kind,
        rawSource: item.preferredUrl,
      );
      final rawSource = item.preferredUrl?.trim();
      if (rawSource != null && rawSource.isNotEmpty) {
        logLegacyMediaBlocked(
          surface: 'lesson_page_trailing_media',
          mediaType: item.kind,
          rawSource: rawSource,
          reason: _isAuthProtectedLessonMediaPath(rawSource)
              ? 'legacy_path'
              : 'raw_media_url',
        );
      }
      return ListTile(
        leading: Icon(_iconForKind()),
        title: Text(_fileName),
        subtitle: const Text('Media saknar ID och kan inte renderas'),
      );
    }

    final mediaRepo = ref.watch(mediaRepositoryProvider);
    final pipelineRepo = ref.watch(mediaPipelineRepositoryProvider);

    if (item.kind == 'image') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _LessonResolvedMedia(
          initialUrl: '',
          lessonMediaId: normalizedLessonMediaId,
          mediaType: 'image',
          builder: (context, resolvedUrl) =>
              AveliLessonImage(src: resolvedUrl, alt: _fileName),
          placeholderBuilder:
              (
                context, {
                required isLoading,
                required failureState,
                required onRetry,
              }) => _LessonMediaResolvePlaceholder(
                mediaType: 'image',
                isLoading: isLoading,
                failureState: failureState,
                onRetry: onRetry,
              ),
        ),
      );
    }

    if (item.kind == 'audio' && item.mediaAssetId != null) {
      final state = item.mediaState ?? 'uploaded';
      if (state != 'ready') {
        final label = state == 'failed'
            ? 'Ljudet kunde inte bearbetas.'
            : 'Ljudet bearbetas…';
        return ListTile(
          leading: Icon(_iconForKind()),
          title: Text(_fileName),
          subtitle: Text(label),
        );
      }
      final future = resolveLessonMediaPlaybackUrl(
        item: item,
        mediaRepository: mediaRepo,
        pipelineRepository: pipelineRepo,
      );
      return FutureBuilder<String?>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            );
          }
          final playbackUrl = snapshot.data;
          final url = _normalizeInlinePlaybackUrl(playbackUrl);
          if (url == null) {
            return _buildUnavailableMediaTile();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LessonGlassMediaWrapper(
              child: AveliLessonMediaPlayer(
                playbackUrl: url,
                title: _fileName,
                kind: 'audio',
              ),
            ),
          );
        },
      );
    }

    if (item.kind == 'video') {
      if (!canAttemptLessonMediaPlayback(item)) {
        return _buildUnavailableMediaTile();
      }
      final future = resolveLessonMediaPlaybackUrl(
        item: item,
        mediaRepository: mediaRepo,
        pipelineRepository: pipelineRepo,
      );
      return FutureBuilder<String?>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            );
          }
          final playbackUrl = snapshot.data;
          final url = _normalizeInlinePlaybackUrl(playbackUrl);
          if (url == null) {
            return _buildUnavailableMediaTile();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LessonGlassMediaWrapper(
              child: AveliLessonMediaPlayer(
                playbackUrl: url,
                title: _fileName,
                kind: 'video',
              ),
            ),
          );
        },
      );
    }

    if (item.kind == 'audio') {
      if (!canAttemptLessonMediaPlayback(item)) {
        return _buildUnavailableMediaTile();
      }
      final future = resolveLessonMediaPlaybackUrl(
        item: item,
        mediaRepository: mediaRepo,
        pipelineRepository: pipelineRepo,
      );
      return FutureBuilder<String?>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            );
          }
          final playbackUrl = snapshot.data;
          final url = _normalizeInlinePlaybackUrl(playbackUrl);
          if (url == null) {
            return _buildUnavailableMediaTile();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LessonGlassMediaWrapper(
              child: AveliLessonMediaPlayer(
                playbackUrl: url,
                title: _fileName,
                kind: 'audio',
              ),
            ),
          );
        },
      );
    }

    final documentUrl = resolveLessonMediaDocumentUrl(
      item: item,
      mediaRepository: mediaRepo,
    );
    if (documentUrl == null || documentUrl.trim().isEmpty) {
      return _buildUnavailableMediaTile();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _LessonDownloadCard(
        fileName: _fileName,
        isPdf: isLessonMediaPdf(item),
        onTap: () => launchUrlString(documentUrl),
      ),
    );
  }
}

String? _normalizeInlinePlaybackUrl(String? rawValue) {
  return normalizeVideoPlaybackUrl(rawValue);
}

class _LessonDownloadCard extends StatelessWidget {
  const _LessonDownloadCard({
    required this.fileName,
    required this.isPdf,
    required this.onTap,
  });

  final String fileName;
  final bool isPdf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = isPdf ? 'Ladda ner PDF' : 'Ladda ner fil';
    final accent = isPdf
        ? Icons.picture_as_pdf_outlined
        : Icons.download_rounded;

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
