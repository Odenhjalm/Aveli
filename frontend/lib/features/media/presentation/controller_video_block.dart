import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/media/application/media_playback_controller.dart';
import 'package:aveli/shared/widgets/media_player.dart';

class ControllerVideoBlock extends ConsumerWidget {
  const ControllerVideoBlock({
    super.key,
    required this.mediaId,
    required this.url,
    this.playbackUrlLoader,
    this.title,
    this.controlsMode = InlineVideoControlsMode.lesson,
    this.minimalUi = false,
    this.controlChrome = InlineVideoControlChrome.playPauseAndStop,
    this.semanticLabel,
    this.semanticHint,
    this.containerKey,
    this.surfaceKey,
    this.playerKey,
  });

  final String mediaId;
  final String url;
  final Future<String?> Function()? playbackUrlLoader;
  final String? title;
  final InlineVideoControlsMode controlsMode;
  final bool minimalUi;
  final InlineVideoControlChrome controlChrome;
  final String? semanticLabel;
  final String? semanticHint;
  final Key? containerKey;
  final Key? surfaceKey;
  final Key? playerKey;

  static const double _desktopBreakpoint = 960;
  static const double _desktopMaxWidth = 920;
  static const double _contentMaxWidth = 860;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalizedId = _normalizedMediaId();
    final playbackController = ref.read(
      mediaPlaybackControllerProvider.notifier,
    );
    final playback = ref.watch(mediaPlaybackControllerProvider);
    final isActive =
        playback.currentMediaId == normalizedId &&
        playback.mediaType == MediaPlaybackType.video &&
        playback.isPlaying;
    final activePlayback = _resolveActivePlaybackState(
      playback: playback,
      normalizedMediaId: normalizedId,
    );
    final isLoading = isActive && activePlayback == null;
    final normalizedTitle = title?.trim();
    final label =
        semanticLabel ??
        (normalizedTitle == null || normalizedTitle.isEmpty
            ? 'Lektionsvideo'
            : 'Lektionsvideo: $normalizedTitle');
    final hint =
        semanticHint ??
        (isActive
            ? 'Tryck på videoytan för att pausa eller fortsätta.'
            : 'Tryck på videoytan för att starta videon.');

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
                hint: hint,
                child: KeyedSubtree(
                  key: surfaceKey,
                  child: _buildSurface(
                    context: context,
                    playbackController: playbackController,
                    normalizedMediaId: normalizedId,
                    label: label,
                    hint: hint,
                    isActive: isActive,
                    isLoading: isLoading,
                    playback: activePlayback,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _normalizedMediaId() {
    final trimmedId = mediaId.trim();
    if (trimmedId.isNotEmpty) return trimmedId;
    final trimmedUrl = url.trim();
    if (trimmedUrl.isNotEmpty) return trimmedUrl;
    return 'video-${identityHashCode(this)}';
  }

  Widget _buildSurface({
    required BuildContext context,
    required MediaPlaybackController playbackController,
    required String normalizedMediaId,
    required String label,
    required String hint,
    required bool isActive,
    required bool isLoading,
    required VideoPlaybackState? playback,
  }) {
    final resolvedControls = resolveInlineVideoControls(
      controlsMode: controlsMode,
      minimalUi: minimalUi,
      controlChrome: controlChrome,
    );

    if (playback != null && !isLoading) {
      return InlineVideoPlayer(
        key:
            playerKey ??
            ValueKey<String>('controller-video-$normalizedMediaId'),
        playback: playback,
        autoPlay: true,
        onPlaybackStateChanged: (playing) {
          playbackController.syncVideoPlaybackState(
            mediaId: normalizedMediaId,
            isPlaying: playing,
          );
        },
      );
    }

    final theme = Theme.of(context);
    final placeholderChild = AspectRatio(
      aspectRatio: 16 / 9,
      child: Center(
        child: isLoading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text('Laddar ström...', style: theme.textTheme.bodyMedium),
                ],
              )
            : resolvedControls.minimalUi
            ? Icon(
                Icons.play_arrow_rounded,
                size: 44,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.play_arrow_rounded,
                    size: 46,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Spela video',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );

    return VideoSurfaceTapTarget(
      semanticLabel: label,
      semanticHint: hint,
      onActivate: isLoading
          ? () {}
          : () => _activate(playbackController, normalizedMediaId),
      child: placeholderChild,
    );
  }

  VideoPlaybackState? _resolveActivePlaybackState({
    required MediaPlaybackState playback,
    required String normalizedMediaId,
  }) {
    if (playback.currentMediaId != normalizedMediaId) return null;
    if (playback.mediaType != MediaPlaybackType.video) return null;
    if (!playback.isPlaying || playback.isLoading) return null;
    final activeUrl = (playback.url ?? '').trim();
    if (activeUrl.isEmpty) return null;
    final resolvedTitle = (playback.title ?? title ?? '').trim();
    return tryCreateVideoPlaybackState(
      mediaId: normalizedMediaId,
      url: activeUrl,
      title: resolvedTitle,
      controlsMode: controlsMode,
      controlChrome: controlChrome,
      minimalUi: minimalUi,
    );
  }

  void _activate(
    MediaPlaybackController playbackController,
    String normalizedMediaId,
  ) {
    final current = playbackController.state;
    final alreadyLoading =
        current.currentMediaId == normalizedMediaId &&
        current.mediaType == MediaPlaybackType.video &&
        current.isPlaying &&
        current.isLoading;
    if (alreadyLoading) return;
    final loader = playbackUrlLoader;
    if (loader != null) {
      unawaited(
        playbackController
            .play(
              mediaId: normalizedMediaId,
              mediaType: MediaPlaybackType.video,
              title: title,
              urlLoader: () async {
                final loaded = (await loader())?.trim() ?? '';
                if (loaded.isNotEmpty) return loaded;
                final fallback = url.trim();
                if (fallback.isNotEmpty) return fallback;
                throw StateError('Empty playback URL');
              },
            )
            .catchError((Object _, StackTrace __) {}),
      );
      return;
    }

    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) return;
    unawaited(
      playbackController
          .play(
            mediaId: normalizedMediaId,
            mediaType: MediaPlaybackType.video,
            url: trimmedUrl,
            title: title,
          )
          .catchError((Object _, StackTrace __) {}),
    );
  }
}
