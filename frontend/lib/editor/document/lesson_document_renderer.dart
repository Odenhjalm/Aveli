import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:aveli/shared/media/AveliLessonImage.dart';
import 'package:aveli/shared/media/AveliLessonMediaPlayer.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/widgets/glass_card.dart';

import 'lesson_document.dart';

const double lessonHeadingScaleFactor = 1.6;
const _paperReadingTextColor = Color(0xFF151515);
const _paperReadingLineColor = Color(0x14000000);
const _paperReadingDefaultGlassFontSize = 14.0;
const _paperReadingContentPadding = EdgeInsets.fromLTRB(24, 24, 24, 24);
const _paperReadingTextHeightBehavior = TextHeightBehavior(
  applyHeightToFirstAscent: true,
  applyHeightToLastDescent: true,
);

TextStyle lessonHeadingPresentationStyle(
  ThemeData theme, {
  required int level,
  required Color color,
}) {
  final base = switch (level) {
    1 => theme.textTheme.headlineMedium,
    2 => theme.textTheme.headlineSmall,
    3 => theme.textTheme.titleLarge,
    _ => theme.textTheme.titleMedium,
  };
  final fallbackFontSize = switch (level) {
    1 || 2 => 24.0,
    _ => 20.0,
  };
  return (base ?? TextStyle(fontSize: fallbackFontSize)).copyWith(
    fontSize: (base?.fontSize ?? fallbackFontSize) * lessonHeadingScaleFactor,
    fontWeight: FontWeight.w700,
    height: 1.22,
    color: color,
  );
}

enum LessonDocumentReadingMode { glass, paper }

class LessonDocumentPreviewMedia {
  const LessonDocumentPreviewMedia({
    required this.lessonMediaId,
    required this.mediaType,
    required this.state,
    this.label,
    this.resolvedUrl,
  });

  final String lessonMediaId;
  final String mediaType;
  final String state;
  final String? label;
  final String? resolvedUrl;
}

class LessonDocumentReadingModeToggle extends StatelessWidget {
  const LessonDocumentReadingModeToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final LessonDocumentReadingMode value;
  final ValueChanged<LessonDocumentReadingMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Reading mode',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        ToggleButtons(
          key: const ValueKey<String>('lesson_document_reading_mode_toggle'),
          borderRadius: BorderRadius.circular(999),
          constraints: const BoxConstraints(minHeight: 36, minWidth: 82),
          isSelected: [
            value == LessonDocumentReadingMode.glass,
            value == LessonDocumentReadingMode.paper,
          ],
          onPressed: (index) {
            onChanged(
              index == 0
                  ? LessonDocumentReadingMode.glass
                  : LessonDocumentReadingMode.paper,
            );
          },
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Glass'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Paper'),
            ),
          ],
        ),
      ],
    );
  }
}

class LessonDocumentPaperMetrics {
  const LessonDocumentPaperMetrics({
    required this.glassFontSize,
    required this.glassLineHeight,
    required this.paperFontSize,
    required this.paperLineHeight,
    required this.rowHeight,
    required this.contentPadding,
    required this.baseTextSpec,
  });

  factory LessonDocumentPaperMetrics.resolve(BuildContext context) {
    final theme = Theme.of(context);
    final glassBaseStyle =
        theme.textTheme.bodyMedium ?? DefaultTextStyle.of(context).style;
    final glassFontSize =
        glassBaseStyle.fontSize ?? _paperReadingDefaultGlassFontSize;
    final glassLineHeight = _lineHeightPx(glassBaseStyle);
    final paperFontSize = glassFontSize + 4;
    final paperLineHeight = glassLineHeight + 4;
    final paperBaseStyle = glassBaseStyle.copyWith(
      color: _paperReadingTextColor,
    );
    return LessonDocumentPaperMetrics(
      glassFontSize: glassFontSize,
      glassLineHeight: glassLineHeight,
      paperFontSize: paperFontSize,
      paperLineHeight: paperLineHeight,
      rowHeight: paperLineHeight,
      contentPadding: _paperReadingContentPadding,
      baseTextSpec: _PaperTextSpec.fromGlassStyle(
        glassStyle: paperBaseStyle,
        rowHeight: paperLineHeight,
        color: _paperReadingTextColor,
        exactRequestedLineHeight: paperLineHeight,
      ),
    );
  }

  final double glassFontSize;
  final double glassLineHeight;
  final double paperFontSize;
  final double paperLineHeight;
  final double rowHeight;
  final EdgeInsets contentPadding;
  final _PaperTextSpec baseTextSpec;

  TextStyle get textStyle => baseTextSpec.style;
  StrutStyle get strutStyle => baseTextSpec.strutStyle;

  _PaperTextSpec headingSpec(ThemeData theme, int level) {
    final glassHeadingStyle = lessonHeadingPresentationStyle(
      theme,
      level: level,
      color: _paperReadingTextColor,
    );
    return _PaperTextSpec.fromGlassStyle(
      glassStyle: glassHeadingStyle,
      rowHeight: rowHeight,
      color: _paperReadingTextColor,
      exactRequestedLineHeight: _lineHeightPx(glassHeadingStyle) + 4,
      snapToRows: true,
    );
  }

  _PaperTextSpec markerSpec(Color color) {
    final glassMarkerStyle = textStyle.copyWith(
      fontSize: glassFontSize,
      height: glassLineHeight / glassFontSize,
      fontWeight: FontWeight.w600,
      color: color,
    );
    return _PaperTextSpec.fromGlassStyle(
      glassStyle: glassMarkerStyle,
      rowHeight: rowHeight,
      color: color,
      exactRequestedLineHeight: paperLineHeight,
    );
  }

  double blockGapBetween(LessonBlock current, LessonBlock next) {
    return rowHeight;
  }

  double snapBlockHeight(double rawHeight, {int minRows = 1}) {
    final rows = math.max(minRows, (rawHeight / rowHeight).ceil());
    return rows * rowHeight;
  }
}

class LessonDocumentPreview extends StatelessWidget {
  const LessonDocumentPreview({
    super.key,
    required this.document,
    this.media = const <LessonDocumentPreviewMedia>[],
    this.onLaunchUrl,
    this.readingMode = LessonDocumentReadingMode.glass,
  });

  final LessonDocument document;
  final List<LessonDocumentPreviewMedia> media;
  final ValueChanged<String>? onLaunchUrl;
  final LessonDocumentReadingMode readingMode;

  @override
  Widget build(BuildContext context) {
    if (document.blocks.isEmpty) {
      return const Text('Lektionsinnehall saknas.');
    }
    return switch (readingMode) {
      LessonDocumentReadingMode.glass => _LessonDocumentGlassSurface(
        child: _LessonDocumentViewport(
          child: _LessonDocumentBlockList(
            document: document,
            media: media,
            onLaunchUrl: onLaunchUrl,
            readingMode: readingMode,
          ),
        ),
      ),
      LessonDocumentReadingMode.paper => _LessonDocumentPaperSurface(
        document: document,
        media: media,
        onLaunchUrl: onLaunchUrl,
      ),
    };
  }
}

class _LessonDocumentGlassSurface extends StatelessWidget {
  const _LessonDocumentGlassSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      opacity: 0.16,
      sigmaX: 10,
      sigmaY: 10,
      borderRadius: BorderRadius.circular(22),
      borderColor: Colors.white.withValues(alpha: 0.16),
      child: child,
    );
  }
}

class _LessonDocumentViewport extends StatelessWidget {
  const _LessonDocumentViewport({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          return child;
        }
        return SingleChildScrollView(
          primary: false,
          padding: EdgeInsets.zero,
          child: child,
        );
      },
    );
  }
}

class _LessonDocumentPaperSurface extends StatelessWidget {
  const _LessonDocumentPaperSurface({
    required this.document,
    required this.media,
    required this.onLaunchUrl,
  });

  final LessonDocument document;
  final List<LessonDocumentPreviewMedia> media;
  final ValueChanged<String>? onLaunchUrl;

  @override
  Widget build(BuildContext context) {
    final metrics = LessonDocumentPaperMetrics.resolve(context);
    final mediaQuery = MediaQuery.maybeOf(context);
    final content = Padding(
      padding: metrics.contentPadding,
      child: DefaultTextStyle.merge(
        style: metrics.textStyle,
        child: _LessonDocumentBlockList(
          document: document,
          media: media,
          onLaunchUrl: onLaunchUrl,
          readingMode: LessonDocumentReadingMode.paper,
          paperMetrics: metrics,
        ),
      ),
    );
    final child = mediaQuery == null
        ? content
        : MediaQuery(
            data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),
            child: content,
          );

    return _LessonDocumentViewport(
      child: DecoratedBox(
        key: const ValueKey<String>('lesson_document_paper_reading_surface'),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _PaperGuideLinesPainter(
                      firstGuideY:
                          metrics.contentPadding.top + metrics.rowHeight,
                      rowHeight: metrics.rowHeight,
                      bottomInset: metrics.contentPadding.bottom,
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _PaperGuideLinesPainter extends CustomPainter {
  const _PaperGuideLinesPainter({
    required this.firstGuideY,
    required this.rowHeight,
    required this.bottomInset,
  });

  final double firstGuideY;
  final double rowHeight;
  final double bottomInset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _paperReadingLineColor
      ..strokeWidth = 1;
    for (var y = firstGuideY; y <= size.height - bottomInset; y += rowHeight) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PaperGuideLinesPainter oldDelegate) {
    return oldDelegate.firstGuideY != firstGuideY ||
        oldDelegate.rowHeight != rowHeight ||
        oldDelegate.bottomInset != bottomInset;
  }
}

class _LessonDocumentBlockList extends StatelessWidget {
  const _LessonDocumentBlockList({
    required this.document,
    required this.media,
    required this.onLaunchUrl,
    required this.readingMode,
    this.paperMetrics,
  });

  final LessonDocument document;
  final List<LessonDocumentPreviewMedia> media;
  final ValueChanged<String>? onLaunchUrl;
  final LessonDocumentReadingMode readingMode;
  final LessonDocumentPaperMetrics? paperMetrics;

  @override
  Widget build(BuildContext context) {
    final mediaByLessonMediaId = {
      for (final item in media) item.lessonMediaId: item,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < document.blocks.length; index += 1) ...[
          _LessonDocumentBlock(
            block: document.blocks[index],
            mediaByLessonMediaId: mediaByLessonMediaId,
            onLaunchUrl: onLaunchUrl,
            readingMode: readingMode,
            paperMetrics: paperMetrics,
          ),
          if (index < document.blocks.length - 1)
            SizedBox(
              height:
                  paperMetrics?.blockGapBetween(
                    document.blocks[index],
                    document.blocks[index + 1],
                  ) ??
                  12,
            ),
        ],
      ],
    );
  }
}

class _LessonDocumentBlock extends StatelessWidget {
  const _LessonDocumentBlock({
    required this.block,
    required this.mediaByLessonMediaId,
    required this.onLaunchUrl,
    required this.readingMode,
    required this.paperMetrics,
  });

  final LessonBlock block;
  final Map<String, LessonDocumentPreviewMedia> mediaByLessonMediaId;
  final ValueChanged<String>? onLaunchUrl;
  final LessonDocumentReadingMode readingMode;
  final LessonDocumentPaperMetrics? paperMetrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPaper = readingMode == LessonDocumentReadingMode.paper;
    if (block is LessonParagraphBlock) {
      return _DocumentInlineRunsView(
        children: (block as LessonParagraphBlock).children,
        onLaunchUrl: onLaunchUrl,
        paperSpec: paperMetrics?.baseTextSpec,
      );
    }
    if (block is LessonHeadingBlock) {
      final heading = block as LessonHeadingBlock;
      if (!isPaper) {
        return DefaultTextStyle.merge(
          style: lessonHeadingPresentationStyle(
            theme,
            level: heading.level,
            color: theme.colorScheme.onSurface,
          ),
          child: _DocumentInlineRunsView(
            children: heading.children,
            onLaunchUrl: onLaunchUrl,
          ),
        );
      }
      final headingSpec = paperMetrics!.headingSpec(theme, heading.level);
      return DefaultTextStyle.merge(
        style: headingSpec.style,
        child: _DocumentInlineRunsView(
          children: heading.children,
          onLaunchUrl: onLaunchUrl,
          paperSpec: headingSpec,
        ),
      );
    }
    if (block is LessonListBlock) {
      final list = block as LessonListBlock;
      final ordered = list.type == 'ordered_list';
      final markerSpec = paperMetrics?.markerSpec(
        theme.colorScheme.onSurfaceVariant,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < list.items.length; index += 1)
            Padding(
              padding: EdgeInsets.only(bottom: isPaper ? 0 : 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: markerSpec == null
                        ? Text(
                            ordered ? '${index + (list.start ?? 1)}.' : '-',
                            style: DefaultTextStyle.of(context).style.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        : DefaultTextStyle.merge(
                            style: markerSpec.style,
                            child: _DocumentMeasuredSpanView(
                              text: TextSpan(
                                style: markerSpec.style,
                                text: ordered
                                    ? '${index + (list.start ?? 1)}.'
                                    : '-',
                              ),
                              paperSpec: markerSpec,
                            ),
                          ),
                  ),
                  Expanded(
                    child: _DocumentInlineRunsView(
                      children: list.items[index].children,
                      onLaunchUrl: onLaunchUrl,
                      paperSpec: paperMetrics?.baseTextSpec,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    if (block is LessonMediaBlock) {
      final mediaBlock = block as LessonMediaBlock;
      final media = mediaByLessonMediaId[mediaBlock.lessonMediaId];
      return _LessonDocumentMediaBlock(
        block: mediaBlock,
        media: media,
        readingMode: readingMode,
        paperMetrics: paperMetrics,
        onLaunchUrl: onLaunchUrl,
      );
    }
    if (block is LessonCtaBlock) {
      final cta = block as LessonCtaBlock;
      final child = FilledButton(
        onPressed: () => _launchUrl(cta.targetUrl, onLaunchUrl),
        child: Text(cta.label),
      );
      if (!isPaper) {
        return child;
      }
      return _PaperSnapBlock(
        minRows: 2,
        metrics: paperMetrics!,
        child: Align(alignment: Alignment.centerLeft, child: child),
      );
    }
    return const SizedBox.shrink();
  }
}

class _LessonDocumentMediaBlock extends StatelessWidget {
  const _LessonDocumentMediaBlock({
    required this.block,
    required this.media,
    required this.readingMode,
    required this.paperMetrics,
    required this.onLaunchUrl,
  });

  final LessonMediaBlock block;
  final LessonDocumentPreviewMedia? media;
  final LessonDocumentReadingMode readingMode;
  final LessonDocumentPaperMetrics? paperMetrics;
  final ValueChanged<String>? onLaunchUrl;

  @override
  Widget build(BuildContext context) {
    final resolved = media;
    final resolvedUrl = resolved?.resolvedUrl?.trim();
    if (resolved == null ||
        resolved.mediaType != block.mediaType ||
        resolved.state != 'ready' ||
        resolvedUrl == null ||
        resolvedUrl.isEmpty) {
      return _LessonMediaErrorState(mediaType: block.mediaType);
    }
    final label = switch (block.mediaType) {
      'image' => 'Bild',
      'audio' => 'Lektionsljud',
      'video' => 'Lektionsvideo',
      'document' => 'Lektionsfil',
      _ => 'Media',
    };
    final isPaper = readingMode == LessonDocumentReadingMode.paper;
    return switch (block.mediaType) {
      'image' =>
        isPaper
            ? _PaperAspectRatioBlock(
                metrics: paperMetrics!,
                aspectRatio: 4 / 3,
                child: AveliLessonImage(src: resolvedUrl, alt: label),
              )
            : AveliLessonImage(src: resolvedUrl, alt: label),
      'audio' => _AdaptiveMediaCardBlock(
        metrics: paperMetrics,
        readingMode: readingMode,
        minRows: isPaper ? 4 : 1,
        child: AveliLessonMediaPlayer(
          mediaUrl: resolvedUrl,
          title: label,
          kind: 'audio',
          preferLessonLayout: true,
        ),
      ),
      'video' =>
        isPaper
            ? _PaperAspectRatioBlock(
                metrics: paperMetrics!,
                aspectRatio: 16 / 9,
                child: AveliLessonMediaPlayer(
                  mediaUrl: resolvedUrl,
                  title: label,
                  kind: 'video',
                  preferLessonLayout: true,
                ),
              )
            : _AdaptiveMediaCardBlock(
                metrics: paperMetrics,
                readingMode: readingMode,
                child: AveliLessonMediaPlayer(
                  mediaUrl: resolvedUrl,
                  title: label,
                  kind: 'video',
                  preferLessonLayout: true,
                ),
              ),
      'document' => _LessonDocumentDownloadCard(
        metrics: paperMetrics,
        readingMode: readingMode,
        fileName: label,
        onTap: () => _launchUrl(resolvedUrl, onLaunchUrl),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _LessonDocumentDownloadCard extends StatelessWidget {
  const _LessonDocumentDownloadCard({
    required this.metrics,
    required this.readingMode,
    required this.fileName,
    required this.onTap,
  });

  final LessonDocumentPaperMetrics? metrics;
  final LessonDocumentReadingMode readingMode;
  final String fileName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const label = 'Ladda ner dokument';
    const accent = Icons.description_outlined;
    final card = Material(
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
                child: const Padding(
                  padding: EdgeInsets.all(10),
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
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return _AdaptiveMediaCardBlock(
      metrics: metrics,
      readingMode: readingMode,
      minRows: readingMode == LessonDocumentReadingMode.paper ? 4 : 1,
      child: card,
    );
  }
}

class _AdaptiveMediaCardBlock extends StatelessWidget {
  const _AdaptiveMediaCardBlock({
    required this.metrics,
    required this.readingMode,
    required this.child,
    this.minRows = 1,
  });

  final LessonDocumentPaperMetrics? metrics;
  final LessonDocumentReadingMode readingMode;
  final Widget child;
  final int minRows;

  static const double _maxWidth = 860;

  @override
  Widget build(BuildContext context) {
    final surface = Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: readingMode == LessonDocumentReadingMode.paper
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: child,
              )
            : GlassCard(
                padding: const EdgeInsets.all(8),
                borderRadius: BorderRadius.circular(16),
                borderColor: Colors.white.withValues(alpha: 0.16),
                child: child,
              ),
      ),
    );
    if (readingMode != LessonDocumentReadingMode.paper || metrics == null) {
      return surface;
    }
    return _PaperSnapBlock(metrics: metrics!, minRows: minRows, child: surface);
  }
}

class _PaperAspectRatioBlock extends StatelessWidget {
  const _PaperAspectRatioBlock({
    required this.metrics,
    required this.aspectRatio,
    required this.child,
    this.minRows = 1,
  });

  final LessonDocumentPaperMetrics metrics;
  final double aspectRatio;
  final Widget child;
  final int minRows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0.0;
        if (maxWidth <= 0) {
          return child;
        }
        final rawHeight = maxWidth / aspectRatio;
        final snappedHeight = metrics.snapBlockHeight(
          rawHeight,
          minRows: minRows,
        );
        return SizedBox(
          height: snappedHeight,
          child: Center(
            child: AspectRatio(aspectRatio: aspectRatio, child: child),
          ),
        );
      },
    );
  }
}

class _PaperSnapBlock extends StatelessWidget {
  const _PaperSnapBlock({
    required this.metrics,
    required this.child,
    this.minRows = 1,
  });

  final LessonDocumentPaperMetrics metrics;
  final Widget child;
  final int minRows;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: metrics.rowHeight * minRows,
      child: Center(child: child),
    );
  }
}

class _LessonMediaErrorState extends StatelessWidget {
  const _LessonMediaErrorState({required this.mediaType});

  final String mediaType;

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
            'Lektionsmedia kunde inte laddas.',
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

class _DocumentInlineRunsView extends StatelessWidget {
  const _DocumentInlineRunsView({
    required this.children,
    this.onLaunchUrl,
    this.paperSpec,
  });

  final List<LessonTextRun> children;
  final ValueChanged<String>? onLaunchUrl;
  final _PaperTextSpec? paperSpec;

  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final text = TextSpan(
      style: defaultStyle,
      children: [
        for (final run in children)
          TextSpan(
            text: run.text,
            style: lessonTextRunStyle(defaultStyle, run),
            recognizer: _recognizerForRun(run),
          ),
      ],
    );
    if (paperSpec == null) {
      return RichText(text: text);
    }
    return _DocumentMeasuredSpanView(text: text, paperSpec: paperSpec!);
  }

  GestureRecognizer? _recognizerForRun(LessonTextRun run) {
    final launch = onLaunchUrl;
    if (launch == null) return null;
    for (final mark in run.marks) {
      if (mark is LessonLinkMark) {
        return TapGestureRecognizer()..onTap = () => launch(mark.href);
      }
    }
    return null;
  }
}

class _DocumentMeasuredSpanView extends StatelessWidget {
  const _DocumentMeasuredSpanView({
    required this.text,
    required this.paperSpec,
  });

  final TextSpan text;
  final _PaperTextSpec paperSpec;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : double.infinity;
        final richText = RichText(
          text: text,
          strutStyle: paperSpec.strutStyle,
          textScaler: TextScaler.noScaling,
          textHeightBehavior: _paperReadingTextHeightBehavior,
        );
        if (!maxWidth.isFinite) {
          return richText;
        }
        final painter = TextPainter(
          text: text,
          textDirection: Directionality.of(context),
          textScaler: TextScaler.noScaling,
          strutStyle: paperSpec.strutStyle,
          textHeightBehavior: _paperReadingTextHeightBehavior,
        )..layout(maxWidth: maxWidth);
        final lineCount = math.max(1, painter.computeLineMetrics().length);
        return SizedBox(
          height: lineCount * paperSpec.lineHeightPx,
          child: Align(alignment: Alignment.topLeft, child: richText),
        );
      },
    );
  }
}

TextStyle lessonTextRunStyle(TextStyle base, LessonTextRun run) {
  var style = base;
  for (final mark in run.marks) {
    switch (mark.type) {
      case 'bold':
        style = style.copyWith(fontWeight: FontWeight.w700);
        break;
      case 'italic':
        style = style.copyWith(fontStyle: FontStyle.italic);
        break;
      case 'underline':
        style = style.copyWith(decoration: TextDecoration.underline);
        break;
      case 'link':
        style = style.copyWith(
          color: Colors.blueAccent,
          decoration: TextDecoration.underline,
        );
        break;
    }
  }
  return style;
}

class _PaperTextSpec {
  const _PaperTextSpec({
    required this.style,
    required this.strutStyle,
    required this.lineHeightPx,
  });

  factory _PaperTextSpec.fromGlassStyle({
    required TextStyle glassStyle,
    required double rowHeight,
    required Color color,
    required double exactRequestedLineHeight,
    bool snapToRows = false,
  }) {
    final glassFontSize =
        glassStyle.fontSize ?? _paperReadingDefaultGlassFontSize;
    final paperFontSize = glassFontSize + 4;
    var lineHeightPx = exactRequestedLineHeight;
    if (snapToRows) {
      final rowSpan = math.max(
        1,
        (exactRequestedLineHeight / rowHeight).round(),
      );
      lineHeightPx = rowSpan * rowHeight;
    }
    final heightFactor = lineHeightPx / paperFontSize;
    final style = glassStyle.copyWith(
      fontSize: paperFontSize,
      height: heightFactor,
      color: color,
    );
    return _PaperTextSpec(
      style: style,
      strutStyle: StrutStyle(
        fontSize: paperFontSize,
        height: heightFactor,
        leading: 0,
        forceStrutHeight: true,
      ),
      lineHeightPx: lineHeightPx,
    );
  }

  final TextStyle style;
  final StrutStyle strutStyle;
  final double lineHeightPx;
}

double _lineHeightPx(TextStyle style) {
  final fontSize = style.fontSize ?? _paperReadingDefaultGlassFontSize;
  return fontSize * (style.height ?? 1);
}

void _launchUrl(String url, ValueChanged<String>? onLaunchUrl) {
  final handler = onLaunchUrl;
  if (handler != null) {
    handler(url);
    return;
  }
  unawaited(launchUrlString(url, mode: LaunchMode.externalApplication));
}
