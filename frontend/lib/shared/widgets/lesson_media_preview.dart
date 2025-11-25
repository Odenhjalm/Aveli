import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../utils/media_kit_support.dart';
import 'inline_audio_player.dart';
import 'media_player.dart' show InlineVideoPlayer;

/// Controller-less media preview for course editor.
///
/// Uses `media_kit` to render video/audio without exposing controls. Useful
/// when admins/teachers just need to verify an upload inline.
class LessonMediaPreview extends StatefulWidget {
  const LessonMediaPreview({
    super.key,
    required this.source,
    this.aspectRatio = 16 / 9,
    this.autoplay = true,
    this.loop = true,
    this.caption,
  });

  final String source;
  final double aspectRatio;
  final bool autoplay;
  final bool loop;
  final String? caption;

  @override
  State<LessonMediaPreview> createState() => _LessonMediaPreviewState();
}

class _LessonMediaPreviewState extends State<LessonMediaPreview> {
  late final bool _useMediaKit;
  Player? _player;
  VideoController? _videoController;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _stateSub;
  StreamSubscription<Object>? _errorSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  String? _errorMessage;
  bool _isVideo = false;

  @override
  void initState() {
    super.initState();
    _useMediaKit = mediaKitVideoEnabled();
    if (_useMediaKit) {
      _player = Player();
    }
    _isVideo = _looksLikeVideo(widget.source);
    if (_useMediaKit && _isVideo && _player != null) {
      final config = mediaKitVideoConfiguration();
      _videoController = config != null
          ? VideoController(_player!, configuration: config)
          : VideoController(_player!);
    }
    _listenToStreams();
    _open();
  }

  bool _looksLikeVideo(String source) {
    final lower = source.toLowerCase();
    const videoExtensions = ['.mp4', '.mov', '.webm', '.mkv', '.avi', '.m4v'];
    return videoExtensions.any(lower.endsWith);
  }

  void _listenToStreams() {
    final player = _player;
    if (!_useMediaKit || player == null) return;
    _positionSub = player.stream.position.listen((value) {
      if (!mounted) return;
      setState(() => _position = value);
    });
    _durationSub = player.stream.duration.listen((value) {
      if (!mounted) return;
      setState(() => _duration = value);
    });
    _stateSub = player.stream.playing.listen((value) {
      if (!mounted) return;
      setState(() => _isPlaying = value);
    });
    _errorSub = player.stream.error.listen((error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    });
  }

  Future<void> _open() async {
    final player = _player;
    if (!_useMediaKit || player == null) return;
    try {
      await player.open(Media(widget.source), play: widget.autoplay);
      if (widget.loop) {
        await player.setPlaylistMode(PlaylistMode.loop);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.toString());
      }
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _errorSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_useMediaKit) {
      if (_isVideo) {
        return _PreviewContainer(
          aspectRatio: widget.aspectRatio,
          child: InlineVideoPlayer(
            url: widget.source,
            title: widget.caption,
            autoPlay: widget.autoplay,
          ),
        );
      }
      return _PreviewContainer(
        aspectRatio: 4 / 3,
        child: InlineAudioPlayer(url: widget.source, title: widget.caption),
      );
    }

    if (_errorMessage != null) {
      return _PreviewContainer(
        aspectRatio: widget.aspectRatio,
        child: _ErrorOverlay(message: _errorMessage!),
      );
    }

    if (_isVideo && _videoController != null) {
      return _PreviewContainer(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Video(controller: _videoController!, fit: BoxFit.cover),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ProgressBar(position: _position, duration: _duration),
            ),
            if (widget.caption != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _CaptionChip(text: widget.caption!),
              ),
          ],
        ),
      );
    }

    // Fallback to audio representation without controls.
    return _PreviewContainer(
      aspectRatio: 4 / 3,
      child: _AudioPreview(
        position: _position,
        duration: _duration,
        playing: _isPlaying,
        caption: widget.caption,
      ),
    );
  }
}

class _PreviewContainer extends StatelessWidget {
  const _PreviewContainer({required this.aspectRatio, required this.child});

  final double aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.06),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final ratio = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return LinearProgressIndicator(
      value: ratio.isNaN ? 0 : ratio,
      minHeight: 4,
      backgroundColor: Colors.black.withValues(alpha: 0.25),
      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
    );
  }
}

class _CaptionChip extends StatelessWidget {
  const _CaptionChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: theme.colorScheme.error),
          const SizedBox(height: 8),
          Text(
            'Kunde inte spela media',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AudioPreview extends StatelessWidget {
  const _AudioPreview({
    required this.position,
    required this.duration,
    required this.playing,
    this.caption,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.graphic_eq,
            size: 48,
            color: playing ? theme.colorScheme.primary : theme.iconTheme.color,
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: ratio.isNaN ? 0 : ratio,
            backgroundColor: theme.dividerColor.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 12),
            Text(
              caption!,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
