import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

class AveliLessonMediaPlayer extends StatefulWidget {
  const AveliLessonMediaPlayer({
    super.key,
    required this.playbackUrl,
    required this.title,
    required this.kind,
  });

  final String playbackUrl;
  final String title;
  final String kind;

  @override
  State<AveliLessonMediaPlayer> createState() => _AveliLessonMediaPlayerState();
}

class _AveliLessonMediaPlayerState extends State<AveliLessonMediaPlayer> {
  @override
  Widget build(BuildContext context) {
    final kind = widget.kind.trim().toLowerCase();
    final url = widget.playbackUrl.trim();
    final title = widget.title.trim();

    if (!_isValidPlaybackUrl(url)) {
      return _MediaPlaceholder(
        kind: kind,
        message: 'Media saknas eller stöds inte längre',
      );
    }

    if (kind == 'video') {
      return _VideoRenderer(playbackUrl: url, title: title);
    }
    if (kind == 'audio') {
      return _AudioRenderer(playbackUrl: url, title: title);
    }

    return _MediaPlaceholder(kind: kind, message: 'Mediaformat stöds inte');
  }
}

bool _isValidPlaybackUrl(String url) {
  if (url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return false;
  return uri.host.isNotEmpty;
}

class _VideoRenderer extends StatefulWidget {
  const _VideoRenderer({required this.playbackUrl, required this.title});

  final String playbackUrl;
  final String title;

  @override
  State<_VideoRenderer> createState() => _VideoRendererState();
}

class _VideoRendererState extends State<_VideoRenderer> {
  static const BorderRadius _borderRadius = BorderRadius.all(
    Radius.circular(12),
  );

  VideoPlayerController? _controller;
  bool _initializing = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _configureController();
  }

  @override
  void didUpdateWidget(covariant _VideoRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackUrl == widget.playbackUrl) return;
    _disposeController();
    _configureController();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _configureController() {
    _initializing = true;
    _hasError = false;
    final uri = Uri.tryParse(widget.playbackUrl);
    if (uri == null) {
      _initializing = false;
      _hasError = true;
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    unawaited(
      controller
          .initialize()
          .then((_) {
            if (!mounted || !identical(controller, _controller)) return;
            setState(() {
              _initializing = false;
              _hasError = false;
            });
          })
          .catchError((Object _, StackTrace __) {
            if (!mounted || !identical(controller, _controller)) return;
            setState(() {
              _initializing = false;
              _hasError = true;
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
    } catch (_) {
      if (!mounted || !identical(controller, _controller)) return;
      setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_hasError) {
      return const _MediaPlaceholder(
        kind: 'video',
        message: 'Media saknas eller stöds inte längre',
      );
    }
    if (_initializing ||
        controller == null ||
        !controller.value.isInitialized) {
      return _loading(context, aspectRatio: 16 / 9);
    }

    final isPlaying = controller.value.isPlaying;
    final aspectRatio = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;
    final semanticTitle = widget.title.isEmpty ? 'Video' : widget.title;

    return ClipRRect(
      borderRadius: _borderRadius,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(aspectRatio: aspectRatio, child: VideoPlayer(controller)),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlayback,
            ),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: Semantics(
              button: true,
              label: semanticTitle,
              hint: isPlaying
                  ? 'Tryck för att pausa videon.'
                  : 'Tryck för att spela videon.',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loading(BuildContext context, {required double aspectRatio}) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: _borderRadius,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _AudioRenderer extends StatefulWidget {
  const _AudioRenderer({required this.playbackUrl, required this.title});

  final String playbackUrl;
  final String title;

  @override
  State<_AudioRenderer> createState() => _AudioRendererState();
}

class _AudioRendererState extends State<_AudioRenderer> {
  static const BorderRadius _borderRadius = BorderRadius.all(
    Radius.circular(12),
  );

  late final AudioPlayer _player;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _initializing = true;
  bool _hasError = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _bindStreams();
    unawaited(_loadSource());
  }

  @override
  void didUpdateWidget(covariant _AudioRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackUrl == widget.playbackUrl) return;
    unawaited(_loadSource());
  }

  @override
  void dispose() {
    unawaited(_durationSub?.cancel());
    unawaited(_positionSub?.cancel());
    unawaited(_playerStateSub?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  void _bindStreams() {
    _durationSub = _player.durationStream.listen((duration) {
      if (!mounted) return;
      setState(() => _duration = duration ?? Duration.zero);
    });
    _positionSub = _player.positionStream.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
    });
    _playerStateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      final completed = state.processingState == ProcessingState.completed;
      if (completed) {
        unawaited(_player.seek(Duration.zero));
      }
      setState(() {
        _isPlaying = state.playing && !completed;
      });
    });
  }

  Future<void> _loadSource() async {
    setState(() {
      _initializing = true;
      _hasError = false;
      _isPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
    });

    try {
      await _player.stop();
      await _player.setUrl(widget.playbackUrl);
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _hasError = true;
      });
    }
  }

  Future<void> _togglePlayback() async {
    if (_initializing || _hasError) return;
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const _MediaPlaceholder(
        kind: 'audio',
        message: 'Media saknas eller stöds inte längre',
      );
    }
    if (_initializing) {
      return _loading(context);
    }

    final safeDurationMillis = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : 1;
    final sliderValue = _position.inMilliseconds.clamp(0, safeDurationMillis);
    final title = widget.title.isEmpty ? 'Ljud' : widget.title;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: _borderRadius,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: _togglePlayback,
                  icon: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: safeDurationMillis.toDouble(),
                    value: sliderValue.toDouble(),
                    onChanged: _duration.inMilliseconds <= 0
                        ? null
                        : (value) => _player.seek(
                            Duration(milliseconds: value.round()),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _loading(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: _borderRadius,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const SizedBox(
        height: 84,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.kind, required this.message});

  final String kind;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVideo = kind == 'video';
    final icon = isVideo
        ? Icons.ondemand_video_outlined
        : Icons.audiotrack_outlined;
    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (isVideo) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: content,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: SizedBox(height: 84, child: content),
    );
  }
}
