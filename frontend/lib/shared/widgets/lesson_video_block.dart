import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/widgets/media_player.dart';

const Key lessonVideoBlockContainerKey = Key('lesson_video_block_container');
const Key lessonVideoBlockSurfaceKey = Key('lesson_video_block_surface');
const Key lessonVideoBlockPlayerKey = Key('lesson_video_block_player');

class LessonVideoBlock extends StatelessWidget {
  const LessonVideoBlock({
    super.key,
    required this.url,
    this.title,
    this.autoPlay = false,
    this.minimalUi = false,
    this.semanticLabel,
    this.semanticHint,
  });

  final String url;
  final String? title;
  final bool autoPlay;
  final bool minimalUi;
  final String? semanticLabel;
  final String? semanticHint;

  static const double _desktopBreakpoint = 960;
  static const double _desktopMaxWidth = 920;
  static const double _contentMaxWidth = 860;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedTitle = title?.trim();
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
              key: lessonVideoBlockContainerKey,
              constraints: BoxConstraints(
                minWidth: 0,
                maxWidth: constrainedMaxWidth,
              ),
              child: Semantics(
                container: true,
                label: label,
                hint: semanticHint ?? fallbackHint,
                child: DecoratedBox(
                  key: lessonVideoBlockSurfaceKey,
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
                    child: InlineVideoPlayer(
                      key: lessonVideoBlockPlayerKey,
                      url: url,
                      title: title,
                      autoPlay: autoPlay,
                      minimalUi: minimalUi,
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
