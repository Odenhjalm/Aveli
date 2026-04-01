import 'dart:async';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/widgets/media/smooth_video_seekbar.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

class AveliLessonMediaPlayer extends StatefulWidget {
  const AveliLessonMediaPlayer({
    super.key,
    required this.mediaUrl,
    required this.title,
    required this.kind,
    this.preferLessonLayout = false,
  });

  final String mediaUrl;
  final String title;
  final String kind;
  final bool preferLessonLayout;

  @override
  State<AveliLessonMediaPlayer> createState() => _AveliLessonMediaPlayerState();
}

class _AveliLessonMediaPlayerState extends State<AveliLessonMediaPlayer> {
  @override
  Widget build(BuildContext context) {
    switch (widget.kind) {
      case 'video':
        return _VideoRenderer(
          mediaUrl: widget.mediaUrl,
          title: widget.title,
          preferLessonLayout: widget.preferLessonLayout,
        );
      case 'audio':
        return _AudioRenderer(
          mediaUrl: widget.mediaUrl,
          title: widget.title,
          preferLessonLayout: widget.preferLessonLayout,
        );
      default:
        return _MediaErrorState(
          kind: widget.kind,
          message: 'Ogiltig mediatyp: ${widget.kind}',
        );
    }
  }
}

class _VideoRenderer extends StatefulWidget {
  const _VideoRenderer({
    required this.mediaUrl,
    required this.title,
    required this.preferLessonLayout,
  });

  final String mediaUrl;
  final String title;
  final bool preferLessonLayout;

  @override
  State<_VideoRenderer> createState() => _VideoRendererState();
}

class _VideoRendererState extends State<_VideoRenderer> {
  static const BorderRadius _borderRadius = BorderRadius.all(
    Radius.circular(12),
  );

  VideoPlayerController? _controller;
  bool _initializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _configureController();
  }

  @override
  void didUpdateWidget(covariant _VideoRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl == widget.mediaUrl &&
        oldWidget.preferLessonLayout == widget.preferLessonLayout) {
      return;
    }
    _disposeController();
    _configureController();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _configureController() {
    setState(() {
      _initializing = true;
      _error = null;
    });

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.mediaUrl),
    );
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
    final controller = _controller;
    if (_error != null) {
      return _MediaErrorState(kind: 'video', message: _error!);
    }
    if (_initializing ||
        controller == null ||
        !controller.value.isInitialized) {
      return _loading(context, aspectRatio: 16 / 9, label: 'Laddar video...');
    }

    final semanticTitle = widget.title.isEmpty ? 'Video' : widget.title;

    return ClipRRect(
      borderRadius: _borderRadius,
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(controller),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePlayback,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.58),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                  child: SmoothVideoSeekBar(controller: controller),
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 44,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (_, value, _) {
                  final isPlaying = value.isPlaying;
                  return Semantics(
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
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loading(
    BuildContext context, {
    required double aspectRatio,
    required String label,
  }) {
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
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioRenderer extends StatefulWidget {
  const _AudioRenderer({
    required this.mediaUrl,
    required this.title,
    required this.preferLessonLayout,
  });

  final String mediaUrl;
  final String title;
  final bool preferLessonLayout;

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
  String? _error;
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
    if (oldWidget.mediaUrl == widget.mediaUrl &&
        oldWidget.preferLessonLayout == widget.preferLessonLayout) {
      return;
    }
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
      if (!mounted || duration == null) return;
      setState(() => _duration = duration);
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
      _error = null;
      _isPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
    });

    try {
      await _player.stop();
      await _player.setUrl(widget.mediaUrl);
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Ljudet kunde inte laddas.';
      });
    }
  }

  Future<void> _togglePlayback() async {
    if (_initializing || _error != null) return;
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Ljuduppspelningen misslyckades.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _MediaErrorState(kind: 'audio', message: _error!);
    }
    if (_initializing) {
      return _loading(context, label: 'Laddar ljud...');
    }

    final safeDurationMillis = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : 1;
    final sliderValue = _position.inMilliseconds.clamp(0, safeDurationMillis);
    final isLessonView = _isLessonViewContext(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.title.isNotEmpty)
            Text(
              widget.title,
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
                      : (value) =>
                            _player.seek(Duration(milliseconds: value.round())),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (isLessonView) {
      return content;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: _borderRadius,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: content,
    );
  }

  Widget _loading(BuildContext context, {required String label}) {
    final loadingContent = SizedBox(
      height: 84,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 10),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
    if (_isLessonViewContext(context)) {
      return loadingContent;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: _borderRadius,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: loadingContent,
    );
  }

  bool _isLessonViewContext(BuildContext context) {
    return widget.preferLessonLayout ||
        ModalRoute.of(context)?.settings.name == AppRoute.lesson;
  }
}

class _MediaErrorState extends StatelessWidget {
  const _MediaErrorState({required this.kind, required this.message});

  final String kind;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVideo = kind == 'video';
    final content = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 84),
        child: content,
      ),
    );
  }
}
