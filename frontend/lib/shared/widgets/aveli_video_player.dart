import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class AveliVideoPlayer extends StatefulWidget {
  const AveliVideoPlayer({super.key, required this.playbackUrl});

  final String playbackUrl;

  @override
  State<AveliVideoPlayer> createState() => _AveliVideoPlayerState();
}

class _AveliVideoPlayerState extends State<AveliVideoPlayer> {
  static const BorderRadius _borderRadius = BorderRadius.all(
    Radius.circular(12),
  );
  VideoPlayerController? _controller;
  bool _initializing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _configureController();
  }

  @override
  void didUpdateWidget(covariant AveliVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playbackUrl == oldWidget.playbackUrl) return;
    _disposeController();
    _configureController();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _configureController() {
    final uri = Uri.tryParse(widget.playbackUrl);
    final scheme = uri?.scheme;
    if (uri == null ||
        widget.playbackUrl.isEmpty ||
        uri.host.isEmpty ||
        (scheme != 'http' && scheme != 'https')) {
      _initializing = false;
      _error = 'Videon kunde inte laddas.';
      return;
    }
    _initializing = true;
    _error = null;
    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    unawaited(
      controller
          .initialize()
          .then((_) {
            if (!mounted || !identical(controller, _controller)) return;
            setState(() {
              _initializing = false;
              _error = null;
            });
          })
          .catchError((Object error, StackTrace stackTrace) {
            if (!mounted || !identical(controller, _controller)) return;
            setState(() {
              _initializing = false;
              _error = 'Videon kunde inte laddas.';
            });
          }),
    );
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        await controller.play();
      }
      if (!mounted || !identical(controller, _controller)) return;
      setState(() {});
    } catch (error) {
      if (!mounted || !identical(controller, _controller)) return;
      setState(() => _error = 'Videouppspelningen misslyckades.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _errorState(context, _error!);
    }
    final controller = _controller;
    if (_initializing ||
        controller == null ||
        !controller.value.isInitialized) {
      return _loading(context);
    }
    final isPlaying = controller.value.isPlaying;

    return ClipRRect(
      borderRadius: _borderRadius,
      child: Semantics(
        button: true,
        label: 'Video',
        hint: isPlaying
            ? 'Tryck för att pausa videon.'
            : 'Tryck för att spela videon.',
        onTap: _togglePlayback,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePlayback,
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.46),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loading(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: _borderRadius,
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _errorState(BuildContext context, String message) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: _borderRadius,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
