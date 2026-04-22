import 'dart:math';

import 'package:flutter/material.dart';

class InlineAudioPlayerView extends StatelessWidget {
  const InlineAudioPlayerView({
    super.key,
    required this.position,
    required this.duration,
    required this.volume,
    required this.isPlaying,
    required this.isInitializing,
    this.errorMessage,
    this.title,
    this.onDownload,
    this.onTogglePlayPause,
    this.onSeek,
    this.onVolumeChanged,
    this.onToggleMute,
    this.compact = false,
    this.minimalUi = false,
    this.homePlayerUi = false,
  });

  final Duration position;
  final Duration duration;
  final double volume;
  final bool isPlaying;
  final bool isInitializing;
  final String? errorMessage;
  final String? title;
  final Future<void> Function()? onDownload;
  final VoidCallback? onTogglePlayPause;
  final ValueChanged<Duration>? onSeek;
  final ValueChanged<double>? onVolumeChanged;
  final VoidCallback? onToggleMute;
  final bool compact;
  final bool minimalUi;
  final bool homePlayerUi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedMinimalUi = minimalUi || homePlayerUi;
    final resolvedCompact = compact || resolvedMinimalUi;
    final resolvedDuration = duration;
    final maxMillis = max(1, resolvedDuration.inMilliseconds);
    final clampedPosition = position.inMilliseconds.clamp(0, maxMillis);
    final sliderValue = clampedPosition.toDouble();
    final volumeIcon = volume <= 0
        ? Icons.volume_off_rounded
        : volume < 0.5
        ? Icons.volume_down_rounded
        : Icons.volume_up_rounded;
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(resolvedCompact ? 14 : 12),
      side: resolvedCompact
          ? BorderSide(color: Colors.white.withValues(alpha: 0.16))
          : BorderSide.none,
    );
    final titleStyle = resolvedCompact
        ? theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          )
        : theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final timeStyle =
        (resolvedCompact
                ? theme.textTheme.bodySmall
                : theme.textTheme.bodyMedium)
            ?.copyWith(color: theme.colorScheme.onSurface);
    final baseSliderTheme = resolvedCompact
        ? theme.sliderTheme.copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          )
        : theme.sliderTheme;
    final sliderTheme = resolvedMinimalUi
        ? baseSliderTheme.copyWith(
            activeTrackColor: theme.colorScheme.onSurface.withValues(
              alpha: 0.28,
            ),
            inactiveTrackColor: theme.colorScheme.onSurface.withValues(
              alpha: 0.12,
            ),
            thumbColor: theme.colorScheme.onSurface.withValues(alpha: 0.50),
            overlayColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          )
        : baseSliderTheme;
    final volumeSliderTheme = sliderTheme.copyWith(
      thumbShape: RoundSliderThumbShape(
        enabledThumbRadius: resolvedCompact ? 5 : 6,
      ),
      overlayShape: RoundSliderOverlayShape(
        overlayRadius: resolvedCompact ? 8 : 10,
      ),
    );
    final homePlayerSliderTheme = sliderTheme.copyWith(
      trackHeight: 1.75,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
    );
    final padding = homePlayerUi
        ? EdgeInsets.zero
        : resolvedMinimalUi
        ? EdgeInsets.zero
        : resolvedCompact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
        : const EdgeInsets.all(16);

    Widget playbackBody;
    if ((errorMessage ?? '').isNotEmpty) {
      playbackBody = homePlayerUi
          ? Icon(
              Icons.error_outline_rounded,
              size: 22,
              color: theme.colorScheme.error.withValues(alpha: 0.72),
            )
          : Text(
              'Ljudet kunde inte spelas upp.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            );
    } else if (homePlayerUi) {
      playbackBody = Opacity(
        opacity: isInitializing ? 0.64 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('home-player-play-button'),
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 22,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.76),
                  ),
                  onPressed: isInitializing ? null : onTogglePlayPause,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SliderTheme(
                    data: homePlayerSliderTheme,
                    child: Slider(
                      key: const ValueKey('home-player-position-slider'),
                      min: 0,
                      max: maxMillis.toDouble(),
                      value: sliderValue,
                      onChanged:
                          isInitializing ||
                              resolvedDuration.inMilliseconds <= 0 ||
                              onSeek == null
                          ? null
                          : (value) =>
                                onSeek!(Duration(milliseconds: value.round())),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            SliderTheme(
              data: homePlayerSliderTheme,
              child: Slider(
                key: const ValueKey('home-player-volume-slider'),
                min: 0,
                max: 1,
                value: volume,
                onChanged: isInitializing ? null : onVolumeChanged,
              ),
            ),
          ],
        ),
      );
    } else if (isInitializing) {
      playbackBody = Center(
        child: SizedBox(
          width: resolvedCompact ? 22 : 28,
          height: resolvedCompact ? 22 : 28,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else {
      playbackBody = Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: resolvedCompact ? 20 : 24,
                  color: resolvedMinimalUi
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.70)
                      : null,
                ),
                onPressed: onTogglePlayPause,
                visualDensity: resolvedCompact
                    ? VisualDensity.compact
                    : VisualDensity.standard,
                padding: resolvedCompact ? EdgeInsets.zero : null,
                constraints: resolvedCompact
                    ? const BoxConstraints(minWidth: 32, minHeight: 32)
                    : null,
              ),
              Expanded(
                child: SliderTheme(
                  data: sliderTheme,
                  child: Slider(
                    min: 0,
                    max: maxMillis.toDouble(),
                    value: sliderValue,
                    onChanged:
                        resolvedDuration.inMilliseconds <= 0 || onSeek == null
                        ? null
                        : (value) =>
                              onSeek!(Duration(milliseconds: value.round())),
                  ),
                ),
              ),
              if (resolvedMinimalUi && onDownload != null)
                IconButton(
                  tooltip: 'Öppna externt',
                  icon: Icon(
                    Icons.open_in_new_rounded,
                    size: resolvedCompact ? 18 : 20,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                  onPressed: onDownload,
                  visualDensity: VisualDensity.compact,
                )
              else if (!resolvedMinimalUi) ...[
                SizedBox(width: resolvedCompact ? 6 : 8),
                Text(_formatDuration(position), style: timeStyle),
                Text(' / ', style: timeStyle),
                Text(_formatDuration(resolvedDuration), style: timeStyle),
              ],
            ],
          ),
          SizedBox(height: resolvedCompact ? 6 : 10),
          if (resolvedMinimalUi)
            SliderTheme(
              data: volumeSliderTheme,
              child: Slider(
                min: 0,
                max: 1,
                value: volume,
                onChanged: onVolumeChanged,
              ),
            )
          else
            Row(
              children: [
                IconButton(
                  icon: Icon(volumeIcon, size: resolvedCompact ? 18 : 20),
                  onPressed: onToggleMute,
                  visualDensity: resolvedCompact
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                  padding: resolvedCompact ? EdgeInsets.zero : null,
                  constraints: resolvedCompact
                      ? const BoxConstraints(minWidth: 32, minHeight: 32)
                      : null,
                ),
                Expanded(
                  child: SliderTheme(
                    data: volumeSliderTheme,
                    child: Slider(
                      min: 0,
                      max: 1,
                      value: volume,
                      onChanged: onVolumeChanged,
                    ),
                  ),
                ),
              ],
            ),
        ],
      );
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!resolvedMinimalUi && title != null && title!.isNotEmpty) ...[
          Text(title!, style: titleStyle),
          SizedBox(height: resolvedCompact ? 8 : 12),
        ],
        playbackBody,
        if (!resolvedMinimalUi && onDownload != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Öppna externt'),
            ),
          ),
        ],
      ],
    );

    if (resolvedMinimalUi) {
      return Padding(padding: padding, child: content);
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: resolvedCompact ? 0 : null,
      color: resolvedCompact ? Colors.white.withValues(alpha: 0.08) : null,
      shape: cardShape,
      child: Padding(padding: padding, child: content),
    );
  }

  String _formatDuration(Duration value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final totalSeconds = value.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = two(minutes);
    final ss = two(seconds);
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }
}
