import 'dart:async';

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
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/shared/media/AveliLessonImage.dart';
import 'package:aveli/shared/media/AveliLessonMediaPlayer.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/background_layer.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/utils/app_images.dart';
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
            error is AppFailure
                ? error.message
                : 'Laddning av lektionen misslyckades.',
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
      throw StateError('Paketköp är inte tillgängligt i appen.');
    }

    final lessonMediaId = lessonMediaIdFromDocumentLinkUrl(url);
    if (lessonMediaId != null && lessonMediaId.isNotEmpty) {
      final item = detail.media.firstWhere(
        (media) => media.id == lessonMediaId,
        orElse: () => throw StateError('Dokumentet saknar backend-rad.'),
      );
      final resolvedUrl = item.media?.resolvedUrl?.trim();
      if (resolvedUrl == null || resolvedUrl.isEmpty) {
        throw StateError('Dokumentet saknar backend-authored resolved_url.');
      }
      if (!await launchUrlString(
        resolvedUrl,
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('Dokumentet kunde inte öppnas.');
      }
      return;
    }

    if (_isBlockedLessonMediaLink(url)) {
      logLegacyMediaBlocked(
        surface: 'lesson_page_link',
        mediaType: 'document',
        rawSource: url,
        reason: 'noncanonical_link_target',
      );
      throw StateError('Endast backend-auktoriserade dokumentlänkar stöds.');
    }

    if (!await launchUrlString(url, mode: LaunchMode.externalApplication)) {
      throw StateError('Länken kunde inte öppnas.');
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

    final markdownContent = lesson.contentMarkdown;
    if (markdownContent == null || markdownContent.isEmpty) {
      throw StateError('Lektionsinnehåll saknas.');
    }
    final embeddedMediaIds = extractLessonEmbeddedMediaIds(markdownContent);

    bool isEmbedded(LessonMediaItem item) {
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
              onLaunchUrl: (url) => unawaited(_handleLinkTap(context, url)),
            ),
          ),
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

List<LessonSummary> _visibleCourseLessons(List<LessonSummary> lessons) {
  final visible = lessons
      .where(
        (lesson) =>
            lesson.lessonTitle.isNotEmpty &&
            !lesson.lessonTitle.startsWith('_'),
      )
      .toList(growable: false);
  visible.sort((a, b) => a.position.compareTo(b.position));
  return visible;
}

bool _isAllowedTrailingLessonMediaType(LessonMediaItem item) {
  return lessonMediaTypeOf(item) == CanonicalLessonMediaType.document;
}

class LessonPageRenderer extends ConsumerStatefulWidget {
  const LessonPageRenderer({
    super.key,
    required this.markdown,
    this.lessonMedia = const <LessonMediaItem>[],
    this.onLaunchUrl,
  });

  final String markdown;
  final List<LessonMediaItem> lessonMedia;
  final ValueChanged<String>? onLaunchUrl;

  @override
  ConsumerState<LessonPageRenderer> createState() => _LessonPageRendererState();
}

class _LessonPageRendererState extends ConsumerState<LessonPageRenderer> {
  late Future<String> _preparedMarkdownFuture;
  late String _lessonMediaSignature;

  @override
  void initState() {
    super.initState();
    _lessonMediaSignature = _buildLessonMediaSignature(widget.lessonMedia);
    _preparedMarkdownFuture = _createPreparedMarkdownFuture();
  }

  @override
  void didUpdateWidget(covariant LessonPageRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignature = _buildLessonMediaSignature(widget.lessonMedia);
    if (widget.markdown == oldWidget.markdown &&
        _lessonMediaSignature == nextSignature) {
      return;
    }
    _lessonMediaSignature = nextSignature;
    _preparedMarkdownFuture = _createPreparedMarkdownFuture();
  }

  Future<String> _createPreparedMarkdownFuture() {
    final mediaRepo = ref.read(mediaRepositoryProvider);
    final pipelineRepo = ref.read(mediaPipelineRepositoryProvider);
    return prepareLessonMarkdownForRendering(
      mediaRepo,
      widget.markdown,
      lessonMedia: widget.lessonMedia,
      pipelineRepository: pipelineRepo,
    );
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
          return const _LessonRendererErrorState(
            message: 'Lektionsinnehållet kunde inte renderas.',
          );
        }

        final prepared = snapshot.data;
        if (prepared == null || prepared.isEmpty) {
          return const _LessonRendererErrorState(
            message: 'Lektionsinnehållet saknas.',
          );
        }
        return _LessonQuillContent(
          markdown: prepared,
          lessonMedia: widget.lessonMedia,
          onLaunchUrl:
              widget.onLaunchUrl ?? (url) => unawaited(launchUrlString(url)),
        );
      },
    );
  }
}

String _buildLessonMediaSignature(Iterable<LessonMediaItem> items) {
  final buffer = StringBuffer();
  for (final item in items) {
    buffer
      ..write(item.id)
      ..write('|')
      ..write(item.mediaType)
      ..write('|')
      ..write(item.media?.resolvedUrl)
      ..write('|')
      ..write(item.state)
      ..write(';');
  }
  return buffer.toString();
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

class _LessonQuillContent extends StatefulWidget {
  const _LessonQuillContent({
    required this.markdown,
    required this.lessonMedia,
    required this.onLaunchUrl,
  });

  final String markdown;
  final List<LessonMediaItem> lessonMedia;
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
    final document = markdown_to_editor.markdownToEditorDocument(
      markdown: markdown,
    );
    return quill.QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final defaultEmbedBuilders = FlutterQuillEmbeds.editorBuilders(
      videoEmbedConfig: null,
    );
    final embedBuilders = <quill.EmbedBuilder>[
      _LessonVideoEmbedBuilder(lessonMedia: widget.lessonMedia),
      _LessonAudioEmbedBuilder(lessonMedia: widget.lessonMedia),
      _LessonImageEmbedBuilder(lessonMedia: widget.lessonMedia),
      ...defaultEmbedBuilders.where(
        (builder) =>
            builder.key != quill.BlockEmbed.imageType &&
            builder.key != quill.BlockEmbed.videoType &&
            builder.key != AudioBlockEmbed.embedType,
      ),
    ];

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

typedef _LessonResolvedMediaBuilder =
    Widget Function(BuildContext context, String resolvedUrl);

class _LessonResolvedMedia extends ConsumerStatefulWidget {
  const _LessonResolvedMedia({
    required this.item,
    required this.mediaType,
    required this.builder,
  });

  final LessonMediaItem item;
  final String mediaType;
  final _LessonResolvedMediaBuilder builder;

  @override
  ConsumerState<_LessonResolvedMedia> createState() =>
      _LessonResolvedMediaState();
}

class _LessonResolvedMediaState extends ConsumerState<_LessonResolvedMedia> {
  late Future<String> _resolvedUrlFuture;

  @override
  void initState() {
    super.initState();
    _resolvedUrlFuture = _createResolvedUrlFuture();
  }

  @override
  void didUpdateWidget(covariant _LessonResolvedMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id == widget.item.id &&
        oldWidget.item.media?.resolvedUrl == widget.item.media?.resolvedUrl &&
        oldWidget.mediaType == widget.mediaType) {
      return;
    }
    _resolvedUrlFuture = _createResolvedUrlFuture();
  }

  Future<String> _createResolvedUrlFuture() {
    final lessonMediaId = widget.item.id.trim();
    if (lessonMediaId.isEmpty) {
      logMissingLessonMediaIdRender(
        surface: 'lesson_page_render',
        mediaType: widget.mediaType,
        rawSource: null,
      );
      return Future<String>.error(StateError('Lektionsmedia saknar ID.'));
    }
    final resolvedUrl = widget.item.media?.resolvedUrl?.trim();
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return Future<String>.error(
        StateError('Lektionsmedia saknar backend-authored resolved_url.'),
      );
    }
    return Future<String>.value(resolvedUrl);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _resolvedUrlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _LessonMediaLoadingState(mediaType: widget.mediaType);
        }

        if (snapshot.hasError) {
          final lessonMediaId = widget.item.id;
          if (lessonMediaId.isNotEmpty) {
            logUnresolvedLessonMediaRender(
              event: 'UNRESOLVED_LESSON_MEDIA_RENDER',
              surface: 'lesson_page_render',
              mediaType: widget.mediaType,
              lessonMediaId: lessonMediaId,
              error: snapshot.error,
            );
          }
          return _LessonMediaErrorState(
            mediaType: widget.mediaType,
            message: 'Lektionsmedia kunde inte laddas.',
          );
        }

        return widget.builder(context, snapshot.data!);
      },
    );
  }
}

LessonMediaItem _embeddedLessonMediaItem(
  Iterable<LessonMediaItem> lessonMedia,
  String? lessonMediaId,
) {
  final normalizedLessonMediaId = lessonMediaId?.trim() ?? '';
  if (normalizedLessonMediaId.isEmpty) {
    throw StateError('Embedded media saknar lesson_media_id.');
  }
  return lessonMedia.firstWhere(
    (media) => media.id == normalizedLessonMediaId,
    orElse: () => throw StateError('Embedded media saknar backend-rad.'),
  );
}

bool _isBlockedLessonMediaLink(String rawUrl) {
  final normalizedUrl = rawUrl.trim();
  if (normalizedUrl.isEmpty) return false;
  final uri = Uri.tryParse(normalizedUrl);
  if (uri == null) return true;
  if (!uri.hasScheme) return true;
  final normalizedPath = uri.path;
  if (normalizedPath.isEmpty) return false;
  return RegExp(
    r'^/(studio/media|api/media|media/)',
    caseSensitive: false,
  ).hasMatch(normalizedPath);
}

class _LessonMediaLoadingState extends StatelessWidget {
  const _LessonMediaLoadingState({required this.mediaType});

  final String mediaType;

  bool get _isVideo => mediaType == 'video';
  bool get _isImage => mediaType == 'image';

  String _messageText() {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          const SizedBox(height: 12),
          Text(
            _messageText(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
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

    return SizedBox(height: 96, child: Center(child: content));
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

class _LessonImageEmbedBuilder implements quill.EmbedBuilder {
  const _LessonImageEmbedBuilder({required this.lessonMedia});

  final List<LessonMediaItem> lessonMedia;

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
    final alt = lessonMediaAltFromEmbedValue(value);
    final item = _embeddedLessonMediaItem(lessonMedia, lessonMediaId);
    return _LessonResolvedMedia(
      item: item,
      mediaType: 'image',
      builder: (context, resolvedUrl) =>
          AveliLessonImage(src: resolvedUrl, alt: alt),
    );
  }
}

class _LessonResolvedAudioPlayer extends StatelessWidget {
  const _LessonResolvedAudioPlayer({required this.item});

  final LessonMediaItem item;

  @override
  Widget build(BuildContext context) {
    return _LessonResolvedMedia(
      item: item,
      mediaType: 'audio',
      builder: (context, resolvedUrl) => AveliLessonMediaPlayer(
        mediaUrl: resolvedUrl,
        title: '',
        kind: 'audio',
        preferLessonLayout: true,
      ),
    );
  }
}

class _LessonResolvedVideoPlayer extends StatelessWidget {
  const _LessonResolvedVideoPlayer({required this.item});

  final LessonMediaItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _LessonGlassMediaWrapper(
        child: _LessonResolvedMedia(
          item: item,
          mediaType: 'video',
          builder: (context, resolvedUrl) => AveliLessonMediaPlayer(
            mediaUrl: resolvedUrl,
            title: '',
            kind: 'video',
            preferLessonLayout: true,
          ),
        ),
      ),
    );
  }
}

class _LessonAudioEmbedBuilder implements quill.EmbedBuilder {
  const _LessonAudioEmbedBuilder({required this.lessonMedia});

  final List<LessonMediaItem> lessonMedia;

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
    final item = _embeddedLessonMediaItem(lessonMedia, lessonMediaId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _LessonGlassMediaWrapper(
        child: _LessonResolvedAudioPlayer(item: item),
      ),
    );
  }
}

class _LessonVideoEmbedBuilder implements quill.EmbedBuilder {
  const _LessonVideoEmbedBuilder({required this.lessonMedia});

  final List<LessonMediaItem> lessonMedia;

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
    final lessonMediaId = lessonMediaIdFromEmbedValue(value);
    final item = _embeddedLessonMediaItem(lessonMedia, lessonMediaId);
    return _LessonResolvedVideoPlayer(item: item);
  }
}

class _MediaItem extends ConsumerWidget {
  const _MediaItem({required this.item});

  final LessonMediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaType = lessonMediaTypeOf(item);
    final normalizedLessonMediaId = item.id;
    if (normalizedLessonMediaId.isEmpty) {
      logMissingLessonMediaIdRender(
        surface: 'lesson_page_trailing_media',
        mediaType: item.mediaType,
        rawSource: null,
      );
      throw StateError('Lektionsmedia saknar ID.');
    }
    final resolvedUrl = item.media?.resolvedUrl;
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return _LessonMediaErrorState(
        mediaType: mediaType.name,
        message: 'Lektionsmedia kunde inte laddas.',
      );
    }

    switch (mediaType) {
      case CanonicalLessonMediaType.image:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _LessonResolvedMedia(
            item: item,
            mediaType: mediaType.name,
            builder: (context, resolvedUrl) =>
                AveliLessonImage(src: resolvedUrl, alt: 'Bild'),
          ),
        );
      case CanonicalLessonMediaType.audio:
        final state = item.state;
        if (state != 'ready') {
          throw StateError('Ljudmedia är inte redo: $state.');
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _LessonGlassMediaWrapper(
            child: AveliLessonMediaPlayer(
              mediaUrl: resolvedUrl,
              title: 'Ljud',
              kind: mediaType.name,
            ),
          ),
        );
      case CanonicalLessonMediaType.video:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _LessonGlassMediaWrapper(
            child: AveliLessonMediaPlayer(
              mediaUrl: resolvedUrl,
              title: 'Video',
              kind: mediaType.name,
            ),
          ),
        );
      case CanonicalLessonMediaType.document:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _LessonDownloadCard(
            fileName: 'Dokument',
            onTap: () => launchUrlString(resolvedUrl),
          ),
        );
    }
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
