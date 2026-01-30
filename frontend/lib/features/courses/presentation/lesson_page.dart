import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_access_gate.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/media_player.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/utils/snack.dart';

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

  Set<String> _extractEmbeddedMediaIds(String markdown) {
    final ids = <String>{};
    for (final match in _studioMediaIdPattern.allMatches(markdown)) {
      final id = match.group(1);
      if (id != null && id.isNotEmpty) {
        ids.add(id);
      }
    }
    for (final match in _mediaStreamTokenPattern.allMatches(markdown)) {
      final token = match.group(1);
      if (token == null || token.isEmpty) continue;
      final id = _extractMediaIdFromToken(token);
      if (id != null && id.isNotEmpty) {
        ids.add(id);
      }
    }
    return ids;
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

    final remainingMedia = [...mediaItems];

    final markdownContent = _normalizeMarkdown(lesson.contentMarkdown);
    final bundleLinks = _extractBundleLinks(markdownContent);
    final embeddedMediaIds = _extractEmbeddedMediaIds(markdownContent);
    bool isEmbedded(LessonMediaItem item) {
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

    final coreContent = ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(16),
          child: MarkdownBlock(
            data: markdownContent,
            selectable: false,
            config: _buildMarkdownConfig(
              context,
              onLinkTap: (url) => _handleLinkTap(context, ref, url),
            ),
            generator: _lessonMarkdownGenerator,
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
        if (remainingMedia.where((item) => !isEmbedded(item)).isNotEmpty) ...[
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(12),
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...remainingMedia
                    .where((item) => !isEmbedded(item))
                    .map((item) => _MediaItem(item: item)),
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
      maxContentWidth: contentWidth,
    );
  }
}

class _BundleLink {
  const _BundleLink({required this.url, required this.bundleId});
  final String url;
  final String bundleId;
}

MarkdownConfig _buildMarkdownConfig(
  BuildContext context, {
  Future<void> Function(String url)? onLinkTap,
}) {
  final theme = Theme.of(context);
  final textTheme = theme.textTheme;
  final primaryColor = theme.colorScheme.primary;
  final bodyColor = textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface;

  TextStyle resolveStyle(TextStyle? style, TextStyle fallback) {
    final resolved = style ?? fallback;
    return resolved.copyWith(color: style?.color ?? bodyColor);
  }

  return MarkdownConfig(
    configs: [
      PConfig(textStyle: textTheme.bodyMedium ?? const TextStyle(fontSize: 16)),
      H1Config(
        style: resolveStyle(
          textTheme.headlineMedium,
          const TextStyle(
            fontSize: 32,
            height: 40 / 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      H2Config(
        style: resolveStyle(
          textTheme.headlineSmall,
          const TextStyle(
            fontSize: 24,
            height: 30 / 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      H3Config(
        style: resolveStyle(
          textTheme.titleLarge,
          const TextStyle(
            fontSize: 20,
            height: 28 / 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      H4Config(
        style: resolveStyle(
          textTheme.titleMedium,
          const TextStyle(
            fontSize: 18,
            height: 26 / 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      H5Config(
        style: resolveStyle(
          textTheme.titleSmall,
          const TextStyle(
            fontSize: 16,
            height: 24 / 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      H6Config(
        style: resolveStyle(
          textTheme.bodyLarge,
          const TextStyle(
            fontSize: 15,
            height: 22 / 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      LinkConfig(
        style: (textTheme.bodyMedium ?? const TextStyle(fontSize: 16)).copyWith(
          color: primaryColor,
          decoration: TextDecoration.underline,
        ),
        onTap: onLinkTap,
      ),
    ],
  );
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
    String? downloadUrl;
    if (item.preferredUrl != null) {
      try {
        downloadUrl = mediaRepo.resolveUrl(item.preferredUrl!);
      } catch (_) {
        downloadUrl = item.preferredUrl;
      }
    }
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
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(snapshot.data!, fit: BoxFit.cover),
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
      final future = pipelineRepo.fetchPlaybackUrl(item.mediaAssetId!);
      return FutureBuilder<MediaPlaybackUrl>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            );
          }
          if (!snapshot.hasData) {
            return ListTile(
              leading: Icon(_iconForKind()),
              title: Text(_fileName),
              subtitle: const Text('Kunde inte hämta uppspelningslänk.'),
            );
          }
          final playbackUrl = snapshot.data!.playbackUrl.toString();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InlineAudioPlayer(
              url: playbackUrl,
              title: _fileName,
              durationHint: durationHint,
              onDownload: () async {
                await launchUrlString(playbackUrl);
              },
            ),
          );
        },
      );
    }

    if (downloadUrl == null) {
      return ListTile(leading: Icon(_iconForKind()), title: Text(_fileName));
    }

    final url = downloadUrl;

    if (item.kind == 'audio') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InlineAudioPlayer(
          url: url,
          title: _fileName,
          onDownload: () async {
            await launchUrlString(url);
          },
        ),
      );
    }

    if (item.kind == 'video') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InlineVideoPlayer(
          url: url,
          title: _fileName,
          autoPlay: true,
          onDownload: () async {
            await launchUrlString(url);
          },
        ),
      );
    }

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

final RegExp _studioMediaIdPattern = RegExp(
  r'/studio/media/([0-9a-fA-F-]{36})',
);

final RegExp _mediaStreamTokenPattern = RegExp(
  r'/media/stream/([A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+)',
);

String? _extractMediaIdFromToken(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payloadRaw = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final jsonValue = json.decode(payloadRaw);
    if (jsonValue is! Map<String, dynamic>) return null;
    final sub = jsonValue['sub'];
    return sub is String && sub.isNotEmpty ? sub : null;
  } catch (_) {
    return null;
  }
}

class _HtmlAudioTagSyntax extends md.InlineSyntax {
  _HtmlAudioTagSyntax()
    : super(
        r'<audio\\b[^>]*?>[\\s\\S]*?<\\/audio>',
        startCharacter: 0x3c,
        caseSensitive: false,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final raw = match.group(0);
    if (raw == null) return false;
    final element = md.Element('audio', const []);
    element.attributes.addAll(_parseHtmlAttributes(raw));
    parser.addNode(element);
    return true;
  }
}

class _HtmlVideoTagSyntax extends md.InlineSyntax {
  _HtmlVideoTagSyntax()
    : super(
        r'<video\\b[^>]*?>[\\s\\S]*?<\\/video>',
        startCharacter: 0x3c,
        caseSensitive: false,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final raw = match.group(0);
    if (raw == null) return false;
    final element = md.Element('video', const []);
    element.attributes.addAll(_parseHtmlAttributes(raw));
    parser.addNode(element);
    return true;
  }
}

Map<String, String> _parseHtmlAttributes(String html) {
  final attributes = <String, String>{};
  for (final match in _htmlAttributePattern.allMatches(html)) {
    final key = match.group(1);
    if (key == null || key.isEmpty) continue;
    final value = match.group(3) ?? match.group(4) ?? '';
    attributes[key.toLowerCase()] = value;
  }
  return attributes;
}

final RegExp _htmlAttributePattern = RegExp(
  r'''([a-zA-Z_:][a-zA-Z0-9_\-:.]*)\s*=\s*("([^"]*)"|'([^']*)')''',
);

class _AudioNode extends SpanNode {
  _AudioNode(this.attributes);

  final Map<String, String> attributes;

  @override
  InlineSpan build() {
    final src = attributes['src'] ?? '';
    if (src.trim().isEmpty) {
      return const TextSpan();
    }
    return WidgetSpan(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _SignedAudioEmbed(source: src.trim()),
      ),
    );
  }
}

class _VideoNode extends SpanNode {
  _VideoNode(this.attributes);

  final Map<String, String> attributes;

  @override
  InlineSpan build() {
    final src = attributes['src'] ?? '';
    if (src.trim().isEmpty) {
      return const TextSpan();
    }
    return WidgetSpan(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _SignedVideoEmbed(source: src.trim()),
      ),
    );
  }
}

final MarkdownGenerator _lessonMarkdownGenerator = MarkdownGenerator(
  inlineSyntaxList: [
    _HtmlAudioTagSyntax(),
    _HtmlVideoTagSyntax(),
    _HtmlImageTagSyntax(),
  ],
  generators: [
    SpanNodeGeneratorWithTag(
      tag: 'img',
      generator: (e, config, visitor) => _ImageNode(e.attributes),
    ),
    SpanNodeGeneratorWithTag(
      tag: 'audio',
      generator: (e, config, visitor) => _AudioNode(e.attributes),
    ),
    SpanNodeGeneratorWithTag(
      tag: 'video',
      generator: (e, config, visitor) => _VideoNode(e.attributes),
    ),
  ],
);

class _HtmlImageTagSyntax extends md.InlineSyntax {
  _HtmlImageTagSyntax()
    : super(r'<img\\b[^>]*?>', startCharacter: 0x3c, caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final raw = match.group(0);
    if (raw == null) return false;
    final element = md.Element('img', const []);
    element.attributes.addAll(_parseHtmlAttributes(raw));
    parser.addNode(element);
    return true;
  }
}

class _ImageNode extends SpanNode {
  _ImageNode(this.attributes);

  final Map<String, String> attributes;

  @override
  InlineSpan build() {
    final src = attributes['src'] ?? '';
    if (src.trim().isEmpty) {
      return const TextSpan();
    }
    return WidgetSpan(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _SignedImageEmbed(source: src.trim()),
        ),
      ),
    );
  }
}

String? _tryExtractMediaIdFromSource(String source) {
  final studioMatch = _studioMediaIdPattern.firstMatch(source);
  final studioId = studioMatch?.group(1);
  if (studioId != null && studioId.isNotEmpty) {
    return studioId;
  }
  final streamMatch = _mediaStreamTokenPattern.firstMatch(source);
  final token = streamMatch?.group(1);
  if (token == null || token.isEmpty) return null;
  return _extractMediaIdFromToken(token);
}

Future<String> _resolveSignedEmbedUrl(
  MediaRepository repo,
  String source,
) async {
  final mediaId = _tryExtractMediaIdFromSource(source);
  if (mediaId != null && mediaId.isNotEmpty) {
    final signed = await repo.signMedia(mediaId);
    try {
      return repo.resolveUrl(signed.signedUrl);
    } catch (_) {
      return signed.signedUrl;
    }
  }
  try {
    return repo.resolveUrl(source);
  } catch (_) {
    return source;
  }
}

class _SignedImageEmbed extends ConsumerWidget {
  const _SignedImageEmbed({required this.source});

  final String source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mediaRepositoryProvider);
    return FutureBuilder<String>(
      future: _resolveSignedEmbedUrl(repo, source),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Kunde inte ladda bild.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        final url = snapshot.data;
        if (url == null || url.isEmpty) {
          return const SizedBox.shrink();
        }
        return Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Kunde inte ladda bild.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        );
      },
    );
  }
}

class _SignedAudioEmbed extends ConsumerWidget {
  const _SignedAudioEmbed({required this.source});

  final String source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mediaRepositoryProvider);
    return FutureBuilder<String>(
      future: _resolveSignedEmbedUrl(repo, source),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Kunde inte ladda ljud.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        final url = snapshot.data;
        if (url == null || url.isEmpty) {
          return const SizedBox.shrink();
        }
        return InlineAudioPlayer(url: url);
      },
    );
  }
}

class _SignedVideoEmbed extends ConsumerWidget {
  const _SignedVideoEmbed({required this.source});

  final String source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mediaRepositoryProvider);
    return FutureBuilder<String>(
      future: _resolveSignedEmbedUrl(repo, source),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Kunde inte ladda video.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        final url = snapshot.data;
        if (url == null || url.isEmpty) {
          return const SizedBox.shrink();
        }
        return InlineVideoPlayer(url: url, autoPlay: false);
      },
    );
  }
}
