import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';

import '../utils/media_kit_support.dart';
import 'inline_audio_player.dart';

export 'inline_audio_player.dart';

@visibleForTesting
class VideoSurfaceTapTarget extends StatelessWidget {
  const VideoSurfaceTapTarget({
    super.key,
    required this.child,
    required this.onActivate,
    required this.semanticLabel,
    required this.semanticHint,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback onActivate;
  final String semanticLabel;
  final String semanticHint;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: focusNode,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onActivate();
            return null;
          },
        ),
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          label: semanticLabel,
          hint: semanticHint,
          onTap: onActivate,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onActivate,
            child: child,
          ),
        ),
      ),
    );
  }
}

Future<void> showMediaPlayerSheet(
  BuildContext context, {
  required String kind,
  required String url,
  String? title,
  Future<void> Function()? onDownload,
  Duration? durationHint,
}) async {
  if (kind != 'audio' && kind != 'video') {
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      Future<void> Function()? downloadAction;
      if (onDownload != null) {
        downloadAction = () async {
          Navigator.of(sheetContext).maybePop();
          await onDownload();
        };
      }
      final padding = EdgeInsets.fromLTRB(
        16,
        20,
        16,
        16 + MediaQuery.of(sheetContext).viewPadding.bottom,
      );
      return SafeArea(
        child: SingleChildScrollView(
          padding: padding,
          child: kind == 'audio'
              ? InlineAudioPlayer(
                  url: url,
                  title: title,
                  durationHint: durationHint,
                  onDownload: downloadAction,
                )
              : InlineVideoPlayer(
                  url: url,
                  title: title,
                  onDownload: downloadAction,
                ),
        ),
      );
    },
  );
}

class InlineVideoPlayer extends StatefulWidget {
  const InlineVideoPlayer({
    super.key,
    required this.url,
    this.title,
    this.onDownload,
    this.autoPlay = false,
    this.minimalUi = false,
  });

  final String url;
  final String? title;
  final Future<void> Function()? onDownload;
  final bool autoPlay;
  final bool minimalUi;

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  static const BorderRadius _borderRadius = BorderRadius.all(
    Radius.circular(16),
  );
  static const Duration _activationTimeout = Duration(seconds: 12);
  late final bool _useMediaKit;
  VideoPlayerController? _videoController;
  mk.Player? _player;
  VideoController? _mediaVideoController;
  StreamSubscription<mk.VideoParams>? _videoParamsSub;
  StreamSubscription<bool>? _mediaPlayingSub;
  Timer? _activationTimer;
  final FocusNode _surfaceFocusNode = FocusNode(
    debugLabel: 'inline_video_surface',
  );
  double? _mediaAspectRatio;
  bool _mediaKitPlaying = false;
  bool _activated = false;
  bool _initializing = false;
  bool _timedOut = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _useMediaKit = mediaKitVideoEnabled();
    _scheduleAutoActivate();
  }

  @override
  void didUpdateWidget(covariant InlineVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      setState(() {
        _resetControllers();
        _activated = false;
        _initializing = false;
        _error = null;
        _timedOut = false;
        _mediaAspectRatio = null;
      });
      _scheduleAutoActivate();
      return;
    }
    if (widget.autoPlay && !oldWidget.autoPlay) {
      _scheduleAutoActivate();
    }
  }

  void _scheduleAutoActivate() {
    if (!widget.autoPlay) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_activated && !_initializing) {
        _activate();
      }
    });
  }

  void _startActivationTimeout() {
    _activationTimer?.cancel();
    _activationTimer = Timer(_activationTimeout, () {
      _activationTimer = null;
      if (!mounted) return;
      if (_initializing) {
        setState(() {
          _initializing = false;
          _timedOut = true;
        });
      }
    });
  }

  void _clearActivationTimeout() {
    _activationTimer?.cancel();
    _activationTimer = null;
  }

  void _activate() {
    if (_initializing) return;
    final hasRecoverableError = (_activated && _error != null) || _timedOut;
    if (_activated && !hasRecoverableError) return;
    if (hasRecoverableError) {
      _resetControllers();
    }
    setState(() {
      _activated = true;
      _initializing = true;
      _error = null;
      _timedOut = false;
      _mediaAspectRatio = null;
      _mediaKitPlaying = false;
    });
    _startActivationTimeout();
    if (_useMediaKit) {
      unawaited(_prepareMediaKitPlayer());
    } else {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );
      unawaited(_initVideoPlayer());
    }
  }

  void _handleRetry() {
    _resetControllers();
    setState(() {
      _activated = false;
      _initializing = false;
      _error = null;
      _timedOut = false;
      _mediaAspectRatio = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _activate();
    });
  }

  void _resetControllers() {
    _clearActivationTimeout();
    final video = _videoController;
    _videoController = null;
    if (video != null) {
      unawaited(video.dispose());
    }
    final sub = _videoParamsSub;
    _videoParamsSub = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }
    final playingSub = _mediaPlayingSub;
    _mediaPlayingSub = null;
    if (playingSub != null) {
      unawaited(playingSub.cancel());
    }
    final player = _player;
    _player = null;
    _mediaVideoController = null;
    if (player != null) {
      unawaited(player.dispose());
    }
  }

  Future<void> _prepareMediaKitPlayer() async {
    try {
      mk.MediaKit.ensureInitialized();
      if (!mounted) return;
      final player = mk.Player();
      final config = mediaKitVideoConfiguration();
      final controller = config != null
          ? VideoController(player, configuration: config)
          : VideoController(player);
      _player = player;
      _mediaVideoController = controller;
      _listenToMediaKitStreams();
      await _initMediaKit();
    } catch (error) {
      if (!mounted) return;
      _clearActivationTimeout();
      setState(() {
        _initializing = false;
        _error = error.toString();
        _timedOut = false;
      });
    }
  }

  Future<void> _initVideoPlayer() async {
    final controller = _videoController;
    if (controller == null) return;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) return;
      _clearActivationTimeout();
      setState(() {
        _initializing = false;
        _error = null;
        _timedOut = false;
      });
    } catch (error) {
      if (!mounted) return;
      _clearActivationTimeout();
      setState(() {
        _error = error.toString();
        _initializing = false;
        _timedOut = false;
      });
    }
  }

  Future<void> _initMediaKit() async {
    final player = _player;
    final controller = _mediaVideoController;
    if (player == null || controller == null) return;
    try {
      await player.open(mk.Media(widget.url), play: true);
      await player.setPlaylistMode(mk.PlaylistMode.loop);
      await controller.waitUntilFirstFrameRendered;
      if (!mounted) return;
      _clearActivationTimeout();
      setState(() {
        _initializing = false;
        _error = null;
        _timedOut = false;
      });
    } catch (error) {
      if (!mounted) return;
      _clearActivationTimeout();
      setState(() {
        _error = error.toString();
        _initializing = false;
        _timedOut = false;
      });
    }
  }

  void _listenToMediaKitStreams() {
    final player = _player;
    if (player == null) return;
    _videoParamsSub = player.stream.videoParams.listen((params) {
      final aspect = params.aspect;
      final width = params.dw ?? params.w;
      final height = params.dh ?? params.h;
      double? computed;
      if (aspect != null && aspect > 0) {
        computed = aspect;
      } else if (width != null && height != null && width > 0 && height > 0) {
        computed = width / height;
      } else {
        computed = null;
      }
      if (!mounted) return;
      setState(() => _mediaAspectRatio = computed);
    });
    _mediaPlayingSub = player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() => _mediaKitPlaying = playing);
    });
  }

  @override
  void dispose() {
    _resetControllers();
    _surfaceFocusNode.dispose();
    super.dispose();
  }

  String _surfaceLabel() {
    final title = widget.title?.trim();
    if (title == null || title.isEmpty) return 'Videospelare';
    return 'Videospelare: $title';
  }

  String _surfaceHint() {
    if (_timedOut || _error != null) {
      return 'Tryck för att försöka starta videon igen.';
    }
    if (_initializing) {
      return 'Videon laddas just nu.';
    }
    final playing = _isCurrentlyPlaying();
    return playing
        ? 'Tryck för att pausa videon.'
        : 'Tryck för att spela videon.';
  }

  bool _isCurrentlyPlaying() {
    if (!_activated || _initializing || _timedOut || _error != null) {
      return false;
    }
    if (_useMediaKit) {
      return _mediaKitPlaying;
    }
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return false;
    return controller.value.isPlaying;
  }

  void _handleSurfaceToggle() {
    if (!_activated) {
      _activate();
      return;
    }
    if (_timedOut || _error != null) {
      _handleRetry();
      return;
    }
    if (_initializing) return;
    unawaited(_togglePlayback());
  }

  Future<void> _togglePlayback() async {
    if (_useMediaKit) {
      final player = _player;
      if (player == null) return;
      try {
        if (_mediaKitPlaying) {
          await player.pause();
        } else {
          await player.play();
        }
      } catch (_) {
        if (!mounted) return;
        setState(() => _error = 'Kunde inte växla uppspelning.');
      }
      return;
    }

    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        await controller.play();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Kunde inte växla uppspelning.');
    }
  }

  Widget _wrapSurfaceInteraction(Widget child) {
    return VideoSurfaceTapTarget(
      focusNode: _surfaceFocusNode,
      semanticLabel: _surfaceLabel(),
      semanticHint: _surfaceHint(),
      onActivate: _handleSurfaceToggle,
      child: child,
    );
  }

  double _effectiveAspectRatio({
    required double? preferred,
    required double fallback,
  }) {
    if (preferred != null && preferred > 0) {
      return preferred;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    if (!_activated) {
      final theme = Theme.of(context);
      return _wrapWithBorder(
        _wrapSurfaceInteraction(
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Center(
              child: widget.minimalUi
                  ? Icon(
                      Icons.play_arrow_rounded,
                      size: 44,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.70,
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_arrow_rounded,
                          size: 46,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.72,
                          ),
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
          ),
        ),
      );
    }

    if (_initializing) {
      final theme = Theme.of(context);
      return _wrapWithBorder(
        _wrapSurfaceInteraction(
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text('Laddar ström...', style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_timedOut) {
      final theme = Theme.of(context);
      final canPop = Navigator.of(context).canPop();
      return _wrapWithBorder(
        _wrapSurfaceInteraction(
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ingen aktiv ström just nu.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sändningen har inte startat eller är offline.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _handleRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Försök igen'),
                  ),
                  if (canPop) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Tillbaka'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      final theme = Theme.of(context);
      final canPop = Navigator.of(context).canPop();
      return _wrapWithBorder(
        _wrapSurfaceInteraction(
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Media saknas eller stöds inte längre',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _handleRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Försök igen'),
                  ),
                  if (canPop) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Tillbaka'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return _wrapWithBorder(
      _wrapSurfaceInteraction(
        _useMediaKit ? _buildMediaKitPlayer() : _buildVideoPlayer(context),
      ),
    );
  }

  Widget _buildVideoPlayer(BuildContext context) {
    final controller = _videoController;
    if (controller == null) {
      final theme = Theme.of(context);
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(
          child: Text(
            'Media saknas eller stöds inte längre',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        if (value.hasError) {
          final theme = Theme.of(context);
          return AspectRatio(
            aspectRatio: 16 / 9,
            child: Center(
              child: Text(
                'Videofel: ${value.errorDescription}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final aspect = _effectiveAspectRatio(
          preferred: value.aspectRatio > 0
              ? value.aspectRatio
              : _aspectFromSize(value.size),
          fallback: 16 / 9,
        );
        return AspectRatio(aspectRatio: aspect, child: VideoPlayer(controller));
      },
    );
  }

  Widget _buildMediaKitPlayer() {
    final controller = _mediaVideoController;
    final aspect = _effectiveAspectRatio(
      preferred: _mediaAspectRatio,
      fallback: 16 / 9,
    );
    return AspectRatio(
      aspectRatio: aspect,
      child: controller != null
          ? Video(controller: controller, fit: BoxFit.cover)
          : const SizedBox.shrink(),
    );
  }

  double? _aspectFromSize(Size size) {
    if (size.height <= 0 || size.width <= 0) return null;
    return size.width / size.height;
  }

  Widget _wrapWithBorder(Widget child) {
    return ClipRRect(borderRadius: _borderRadius, child: child);
  }
}
