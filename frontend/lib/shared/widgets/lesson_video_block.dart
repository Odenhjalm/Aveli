import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/widgets/media_player.dart';

class LessonVideoBlock extends StatelessWidget {
  const LessonVideoBlock({
    super.key,
    required this.url,
    this.title,
    this.autoPlay = false,
    this.minimalUi = false,
    this.semanticLabel,
    this.semanticHint,
    this.containerKey,
    this.surfaceKey,
    this.playerKey,
  });

  final String url;
  final String? title;
  final bool autoPlay;
  final bool minimalUi;
  final String? semanticLabel;
  final String? semanticHint;
  final Key? containerKey;
  final Key? surfaceKey;
  final Key? playerKey;

  static const double _desktopBreakpoint = 960;
  static const double _desktopMaxWidth = 920;
  static const double _contentMaxWidth = 860;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedTitle = title?.trim();
    final playback = tryCreateVideoPlaybackState(
      mediaId: url,
      url: url,
      title: normalizedTitle ?? '',
      controlsMode: InlineVideoControlsMode.custom,
      controlChrome: InlineVideoControlChrome.hidden,
      minimalUi: minimalUi,
    );
    final label =
        semanticLabel ??
        (normalizedTitle == null || normalizedTitle.isEmpty
            ? 'Lektionsvideo'
            : 'Lektionsvideo: $normalizedTitle');
    const fallbackHint =
        'Aktivera spelknappen med Enter eller mellanslag för att starta videon.';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth >= _desktopBreakpoint
              ? _desktopMaxWidth
              : _contentMaxWidth;
          final constrainedMaxWidth = constraints.maxWidth.isFinite
              ? math.min(maxWidth, constraints.maxWidth)
              : maxWidth;
          return Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              key: containerKey,
              constraints: BoxConstraints(
                minWidth: 0,
                maxWidth: constrainedMaxWidth,
              ),
              child: Semantics(
                container: true,
                label: label,
                hint: semanticHint ?? fallbackHint,
                child: DecoratedBox(
                  key: surfaceKey,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.72),
                    borderRadius: br16,
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.42,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: p8,
                    child: playback == null
                        ? AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Center(
                              child: Text(
                                'Video laddas...',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          )
                        : InlineVideoPlayer(
                            key: playerKey,
                            playback: playback,
                            autoPlay: autoPlay,
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
