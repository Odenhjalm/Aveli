import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:go_router/go_router.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher_string.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_access_gate.dart';
import 'package:aveli/features/media/application/media_playback_controller.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_resolution_mode.dart';
import 'package:aveli/features/media/presentation/controller_video_block.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/app_network_image.dart';
import 'package:aveli/shared/widgets/background_layer.dart';
import 'package:aveli/shared/widgets/media_player.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/utils/lesson_content_pipeline.dart';
import 'package:aveli/shared/utils/lesson_media_playback_resolver.dart';

class LessonPage extends ConsumerStatefulWidget {
  const LessonPage({super.key, required this.lessonId});

  final String lessonId;

  @override
  ConsumerState<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends ConsumerState<LessonPage> {
  ProviderSubscription<AsyncValue<LessonDetailData>>? _lessonSub;
  late final MediaPlaybackController _playbackController;

  @override
  void initState() {
    super.initState();
    _playbackController = ref.read(mediaPlaybackControllerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _playbackController.stop();
    });
    _lessonSub = ref.listenManual<AsyncValue<LessonDetailData>>(
      lessonDetailProvider(widget.lessonId),
      (previous, next) {
        next.whenData(_updateProgress);
      },
    );
  }

  @override
  void dispose() {
    scheduleMicrotask(_playbackController.stop);
    _lessonSub?.close();
    super.dispose();
  }

  Future<void> _updateProgress(LessonDetailData data) async {
    final courseId = data.module?.courseId;
    if (courseId == null || data.courseLessons.isEmpty) return;
    final index = data.courseLessons.indexWhere((l) => l.id == data.lesson.id);
    if (index < 0) return;
    final progress = (index + 1) / data.courseLessons.length;
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
        .map(
          (match) =>
              _BundleLink(url: match.group(0)!, bundleId: match.group(1) ?? ''),
        )
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
    if (!await launchUrlString(url, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        showSnack(context, 'Kunde inte öppna länken.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lesson = detail.lesson;
    final mediaRepo = ref.watch(mediaRepositoryProvider);
    final pipelineRepo = ref.watch(mediaPipelineRepositoryProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = (screenWidth - 32).clamp(720.0, 1200.0).toDouble();
    final mediaItems = detail.media;
    final courseLessons = detail.courseLessons;
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
      final candidateUrls = <String?>[item.downloadUrl, item.signedUrl];
      for (final url in candidateUrls) {
        if (url == null || url.isEmpty) continue;
        if (markdownContent.contains(url)) return true;
        try {
          final resolved = mediaRepo.resolveUrl(url);
          if (markdownContent.contains(resolved)) return true;
        } catch (_) {}
      }
      return false;
    }

    final trailingMedia = mediaItems
        .where((item) => !isEmbedded(item))
        .toList(growable: false);

    final coreContent = ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(16),
          opacity: 0.16,
          sigmaX: 10,
          sigmaY: 10,
          borderRadius: BorderRadius.circular(22),
          borderColor: Colors.white.withValues(alpha: 0.16),
          child: FutureBuilder<String>(
            future: prepareLessonMarkdownForRendering(
              mediaRepo,
              markdownContent,
              lessonMedia: mediaItems,
              pipelineRepository: pipelineRepo,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                );
              }

              final prepared = snapshot.data ?? markdownContent;
              return _LessonQuillContent(
                markdown: prepared,
                onLaunchUrl: (url) =>
                    unawaited(_handleLinkTap(context, ref, url)),
              );
            },
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
    );

    final courseId = detail.module?.courseId;
    final gatedContent = (!lesson.isIntro && courseId != null)
        ? CourseAccessGate(courseId: courseId, child: coreContent)
        : coreContent;

    return AppScaffold(
      title: lesson.title,
      body: gatedContent,
      background: BackgroundLayer(
        image: AppImages.lessonBackground,
        imagePath: AppImages.lessonBackgroundPath,
      ),
      maxContentWidth: contentWidth,
    );
  }
}

class _BundleLink {
  const _BundleLink({required this.url, required this.bundleId});
  final String url;
  final String bundleId;
}

final md.Document _lessonMarkdownDocument = md.Document(
  encodeHtml: false,
  extensionSet: md.ExtensionSet.gitHubWeb,
);

final _lessonMarkdownToDelta = createLessonMarkdownToDelta(
  _lessonMarkdownDocument,
);

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
      final delta = convertLessonMarkdownToDelta(
        _lessonMarkdownToDelta,
        markdown,
      );
      final document = quill.Document.fromDelta(delta);
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
    final imageConfig = QuillEditorImageEmbedConfig(onImageClicked: (_) {});
    final defaultEmbedBuilders = FlutterQuillEmbeds.editorBuilders(
      imageEmbedConfig: imageConfig,
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

    return quill.QuillEditor.basic(
      controller: _controller,
      config: quill.QuillEditorConfig(
        scrollable: false,
        padding: EdgeInsets.zero,
        enableInteractiveSelection: false,
        enableSelectionToolbar: false,
        showCursor: false,
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

class _MissingMediaFallback extends StatelessWidget {
  const _MissingMediaFallback();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.report_gmailerrorred_outlined,
            size: 18,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Media saknas eller stöds inte längre',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonImageEmbedBuilder implements quill.EmbedBuilder {
  const _LessonImageEmbedBuilder();

  static const BorderRadius _borderRadius = BorderRadius.all(
    Radius.circular(12),
  );

  @override
  String get key => quill.BlockEmbed.imageType;

  @override
  bool get expanded => false;

  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(child: widget);

  @override
  String toPlainText(quill.Embed node) =>
      quill.Embed.kObjectReplacementCharacter;

  double? _parseDimension(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    if (raw.endsWith('%')) return null;
    final cleaned = raw.toLowerCase().endsWith('px')
        ? raw.substring(0, raw.length - 2).trim()
        : raw;
    return double.tryParse(cleaned);
  }

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final dynamic value = embedContext.node.value.data;
    final url =
        lessonMediaUrlFromEmbedValue(value) ??
        (value == null ? '' : value.toString());
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: _LessonGlassMediaWrapper(child: _MissingMediaFallback()),
      );
    }

    final widthValue =
        embedContext.node.style.attributes[quill.Attribute.width.key]?.value;
    final heightValue =
        embedContext.node.style.attributes[quill.Attribute.height.key]?.value;
    final width = _parseDimension(widthValue);
    final height = _parseDimension(heightValue);

    Widget child = ClipRRect(
      borderRadius: _borderRadius,
      child: _LessonResolvedImage(url: trimmed),
    );
    if (width != null || height != null) {
      child = SizedBox(width: width, height: height, child: child);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _LessonGlassMediaWrapper(child: child),
    );
  }
}

class _LessonResolvedImage extends ConsumerWidget {
  const _LessonResolvedImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mediaRepositoryProvider);
    var resolved = url;
    try {
      resolved = repo.resolveUrl(url);
    } catch (_) {
      // Keep the raw value when we cannot safely resolve it.
    }

    final uri = Uri.tryParse(resolved);
    final requiresAuth = uri != null && uri.path.startsWith('/studio/media/');

    return AppNetworkImage(
      url: resolved,
      fit: BoxFit.contain,
      requiresAuth: requiresAuth,
      placeholder: const Center(child: CircularProgressIndicator()),
      error: const _MissingMediaFallback(),
    );
  }
}

class _LessonResolvedAudioPlayer extends ConsumerWidget {
  const _LessonResolvedAudioPlayer({required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mediaRepositoryProvider);
    var resolved = url;
    try {
      resolved = repo.resolveUrl(url);
    } catch (_) {
      // Keep the raw value when we cannot safely resolve it.
    }

    final uri = Uri.tryParse(resolved);
    if (uri != null && uri.path.startsWith('/studio/media/')) {
      return const _MissingMediaFallback();
    }

    return InlineAudioPlayer(url: resolved, minimalUi: true);
  }
}

class _LessonResolvedVideoPlayer extends ConsumerWidget {
  const _LessonResolvedVideoPlayer({required this.url, this.lessonMediaId});

  final String url;
  final String? lessonMediaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mediaRepositoryProvider);
    final isAuthenticated = ref.watch(authControllerProvider).isAuthenticated;
    var resolved = url;
    try {
      resolved = repo.resolveUrl(url);
    } catch (_) {
      // Keep the raw value when we cannot safely resolve it.
    }

    final uri = Uri.tryParse(resolved);
    if (uri != null && uri.path.startsWith('/studio/media/')) {
      return const _MissingMediaFallback();
    }
    final mediaId = lessonMediaId?.trim();

    return ControllerVideoBlock(
      key: ValueKey<String>('lesson-embed-video-$resolved'),
      mediaId: 'lesson-embed-$resolved',
      url: resolved,
      playbackUrlLoader: !isAuthenticated || mediaId == null || mediaId.isEmpty
          ? null
          : () => resolveLessonMediaSignedPlaybackUrl(
              lessonMediaId: mediaId,
              mediaRepository: repo,
              mode: MediaResolutionMode.studentRender,
            ),
      controlsMode: InlineVideoControlsMode.lesson,
      semanticLabel: 'Videoblock i lektionen',
      semanticHint: 'Tryck på spela-knappen för att starta lektionsvideon.',
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
    final url =
        lessonMediaUrlFromEmbedValue(value) ??
        (value == null ? '' : value.toString());
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: _LessonGlassMediaWrapper(child: _MissingMediaFallback()),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _LessonGlassMediaWrapper(
        child: _LessonResolvedAudioPlayer(url: trimmed),
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
    final lessonMediaId = lessonMediaIdFromEmbedValue(value);
    final url =
        lessonMediaUrlFromEmbedValue(value) ??
        (value == null ? '' : value.toString());
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: _LessonGlassMediaWrapper(child: _MissingMediaFallback()),
      );
    }
    return _LessonResolvedVideoPlayer(
      url: trimmed,
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
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaRepo = ref.watch(mediaRepositoryProvider);
    final pipelineRepo = ref.watch(mediaPipelineRepositoryProvider);
    final isAuthenticated = ref.watch(authControllerProvider).isAuthenticated;
    final extension = () {
      final name = _fileName;
      final index = name.lastIndexOf('.');
      if (index <= 0 || index == name.length - 1) return null;
      final ext = name.substring(index + 1).toLowerCase();
      return ext.isEmpty ? null : ext;
    }();

    if (item.kind == 'image' && item.preferredUrl != null) {
      final future = mediaRepo.cacheMediaBytes(
        cacheKey: item.mediaId ?? item.id,
        downloadPath: item.preferredUrl!,
        fileExtension: extension,
      );
      return FutureBuilder<Uint8List>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ListTile(
              leading: Icon(_iconForKind()),
              title: Text(_fileName),
              subtitle: const Text('Media saknas eller stöds inte längre'),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _LessonGlassMediaWrapper(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(snapshot.data!, fit: BoxFit.cover),
              ),
            ),
          );
        },
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
      final durationHint = (item.durationSeconds ?? 0) > 0
          ? Duration(seconds: item.durationSeconds!)
          : null;
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
          if (playbackUrl == null || playbackUrl.trim().isEmpty) {
            return ListTile(
              leading: Icon(_iconForKind()),
              title: Text(_fileName),
              subtitle: const Text('Media saknas eller stöds inte längre'),
            );
          }
          final url = playbackUrl.trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LessonGlassMediaWrapper(
              child: InlineAudioPlayer(
                url: url,
                title: _fileName,
                durationHint: durationHint,
                minimalUi: true,
                onDownload: () async {
                  await launchUrlString(url);
                },
              ),
            ),
          );
        },
      );
    }

    if (item.kind == 'video') {
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
          if (playbackUrl == null || playbackUrl.trim().isEmpty) {
            return ListTile(
              leading: Icon(_iconForKind()),
              title: Text(_fileName),
              subtitle: const Text('Media saknas eller stöds inte längre'),
            );
          }
          final url = playbackUrl.trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ControllerVideoBlock(
              key: ValueKey<String>('lesson-media-video-${item.id}'),
              mediaId: item.id,
              url: url,
              playbackUrlLoader: !isAuthenticated
                  ? null
                  : () => resolveLessonMediaPlaybackUrl(
                      item: item,
                      mediaRepository: mediaRepo,
                      pipelineRepository: pipelineRepo,
                      mode: MediaResolutionMode.studentRender,
                    ),
              title: _fileName,
              controlsMode: InlineVideoControlsMode.lesson,
              semanticLabel: 'Videoblock: $_fileName',
              semanticHint: 'Tryck på spela-knappen för att starta videon.',
            ),
          );
        },
      );
    }

    if (item.kind == 'audio') {
      final durationHint = (item.durationSeconds ?? 0) > 0
          ? Duration(seconds: item.durationSeconds!)
          : null;
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
          if (playbackUrl == null || playbackUrl.trim().isEmpty) {
            return ListTile(
              leading: Icon(_iconForKind()),
              title: Text(_fileName),
              subtitle: const Text('Media saknas eller stöds inte längre'),
            );
          }
          final url = playbackUrl.trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LessonGlassMediaWrapper(
              child: InlineAudioPlayer(
                url: url,
                title: _fileName,
                durationHint: durationHint,
                minimalUi: true,
                onDownload: () async {
                  await launchUrlString(url);
                },
              ),
            ),
          );
        },
      );
    }

    String? downloadUrl;
    if (item.preferredUrl != null) {
      try {
        downloadUrl = mediaRepo.resolveUrl(item.preferredUrl!);
      } catch (_) {
        downloadUrl = item.preferredUrl;
      }
    }

    if (downloadUrl == null) {
      return ListTile(leading: Icon(_iconForKind()), title: Text(_fileName));
    }

    final url = downloadUrl;

    return ListTile(
      leading: Icon(_iconForKind()),
      title: Text(_fileName),
      subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        icon: const Icon(Icons.open_in_new_rounded),
        onPressed: () => launchUrlString(url),
      ),
      onTap: () => launchUrlString(url),
    );
  }
}
