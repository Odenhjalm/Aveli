import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'inline_audio_player_contract.dart';

class InlineAudioPlayer extends ConsumerStatefulWidget {
  const InlineAudioPlayer({
    super.key,
    required this.url,
    this.sourceExpiresAt,
    this.sourceLoader,
    this.initialVolumeState,
    this.onVolumeStateChanged,
    this.title,
    this.onDownload,
    this.onEnded,
    this.onError,
    this.durationHint,
    this.compact = false,
    this.autoPlay = false,
    this.minimalUi = false,
    this.homePlayerUi = false,
  });

  final String url;
  final DateTime? sourceExpiresAt;
  final Future<InlineAudioPlaybackSource> Function()? sourceLoader;
  final InlineAudioPlayerVolumeState? initialVolumeState;
  final ValueChanged<InlineAudioPlayerVolumeState>? onVolumeStateChanged;
  final String? title;
  final Future<void> Function()? onDownload;
  final VoidCallback? onEnded;
  final ValueChanged<String>? onError;
  final Duration? durationHint;
  final bool compact;
  final bool autoPlay;
  final bool minimalUi;
  final bool homePlayerUi;

  @override
  ConsumerState<InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends ConsumerState<InlineAudioPlayer> {
  late final AudioPlayer _player;
  late String _activeUrl;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _state = PlayerState.stopped;
  bool _initializing = true;
  String? _error;
  double _volume = 1.0;
  double _lastVolume = 1.0;
  bool _didAutoPlay = false;

  @override
  void initState() {
    super.initState();
    _activeUrl = widget.url;
    _player = AudioPlayer();
    _player.setReleaseMode(ReleaseMode.stop);
    _restoreVolumeState(widget.initialVolumeState, notify: false);
    unawaited(_player.setVolume(_volume));
    _player.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() {
        _duration = duration;
      });
    });
    _player.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() {
        _position = position;
      });
    });
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _state = state;
      });
    });
    _player.onPlayerComplete.listen((event) {
      if (!mounted) return;
      setState(() {
        _position = Duration.zero;
        _state = PlayerState.completed;
      });
      widget.onEnded?.call();
    });

    unawaited(_prepare());
  }

  @override
  void didUpdateWidget(covariant InlineAudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _activeUrl = widget.url;
      unawaited(_prepare());
      return;
    }
    if (oldWidget.initialVolumeState != widget.initialVolumeState) {
      _restoreVolumeState(widget.initialVolumeState, notify: false);
    }
  }

  Future<void> _prepare() async {
    _didAutoPlay = false;
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = null;
        _position = Duration.zero;
        _duration = Duration.zero;
      });
    }
    try {
      await _player.stop();
      await _loadSourceForUrl(_activeUrl);
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = null;
      });
      unawaited(_maybeAutoPlay());
    } catch (error) {
      if (!mounted) return;
      _reportPlaybackError(error.toString());
    }
  }

  Future<void> _loadSourceForUrl(String url) async {
    await _player.setSourceUrl(url);
  }

  Future<void> _maybeAutoPlay() async {
    if (!mounted) return;
    if (!widget.autoPlay) return;
    if (_didAutoPlay) return;
    if (_error != null) return;
    _didAutoPlay = true;
    await _toggle();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_error != null) return;
    try {
      if (_state == PlayerState.playing) {
        await _player.pause();
      } else if (_state == PlayerState.paused && _position > Duration.zero) {
        await _player.resume();
      } else {
        await _player.play(UrlSource(_activeUrl));
      }
    } catch (error) {
      _reportPlaybackError(error.toString());
    }
  }

  void _setVolume(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if (clamped > 0) {
      _lastVolume = clamped;
    }
    setState(() => _volume = clamped);
    unawaited(_player.setVolume(clamped));
    widget.onVolumeStateChanged?.call(_currentVolumeState);
  }

  void _toggleMute() {
    final next = _volume > 0 ? 0.0 : (_lastVolume > 0 ? _lastVolume : 1.0);
    _setVolume(next);
  }

  void _restoreVolumeState(
    InlineAudioPlayerVolumeState? state, {
    required bool notify,
  }) {
    if (state == null) {
      return;
    }
    final nextVolume = state.volume.clamp(0.0, 1.0).toDouble();
    final nextLastVolume = state.lastVolume.clamp(0.0, 1.0).toDouble();
    final effectiveLastVolume = nextLastVolume > 0
        ? nextLastVolume
        : (nextVolume > 0 ? nextVolume : 1.0);
    final changed = _volume != nextVolume || _lastVolume != effectiveLastVolume;
    _volume = nextVolume;
    _lastVolume = effectiveLastVolume;
    unawaited(_player.setVolume(_volume));
    if (!changed) return;
    if (mounted) {
      setState(() {});
    }
    if (notify) {
      widget.onVolumeStateChanged?.call(_currentVolumeState);
    }
  }

  InlineAudioPlayerVolumeState get _currentVolumeState =>
      InlineAudioPlayerVolumeState(volume: _volume, lastVolume: _lastVolume);

  void _reportPlaybackError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _initializing = false;
    });
    widget.onError?.call(message);
  }

  Duration get _effectiveDuration {
    return _duration;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final homePlayerUi = widget.homePlayerUi;
    final minimalUi = widget.minimalUi || homePlayerUi;
    final compact = widget.compact || minimalUi;
    final duration = _effectiveDuration;
    final maxMillis = max(1, duration.inMilliseconds);
    final position = _position.inMilliseconds.clamp(0, maxMillis);
    final sliderValue = position.toDouble();
    final volumeIcon = _volume <= 0
        ? Icons.volume_off_rounded
        : _volume < 0.5
        ? Icons.volume_down_rounded
        : Icons.volume_up_rounded;
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(compact ? 14 : 12),
      side: compact
          ? BorderSide(color: Colors.white.withValues(alpha: 0.16))
          : BorderSide.none,
    );
    final titleStyle = compact
        ? theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          )
        : theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final timeStyle =
        (compact ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
            ?.copyWith(color: theme.colorScheme.onSurface);
    final baseSliderTheme = compact
        ? theme.sliderTheme.copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          )
        : theme.sliderTheme;
    final sliderTheme = minimalUi
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
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: compact ? 5 : 6),
      overlayShape: RoundSliderOverlayShape(overlayRadius: compact ? 8 : 10),
    );
    final homePlayerSliderTheme = sliderTheme.copyWith(
      trackHeight: 1.75,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
    );
    final padding = homePlayerUi
        ? EdgeInsets.zero
        : minimalUi
        ? EdgeInsets.zero
        : compact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
        : const EdgeInsets.all(16);

    Widget playbackBody;
    if (_error != null) {
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
        opacity: _initializing ? 0.64 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('home-player-play-button'),
                  icon: Icon(
                    _state == PlayerState.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 22,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.76),
                  ),
                  onPressed: _initializing ? null : _toggle,
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
                      onChanged: _initializing || duration.inMilliseconds <= 0
                          ? null
                          : (value) => _player.seek(
                              Duration(milliseconds: value.round()),
                            ),
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
                value: _volume,
                onChanged: _initializing ? null : _setVolume,
              ),
            ),
          ],
        ),
      );
    } else if (_initializing) {
      playbackBody = Center(
        child: SizedBox(
          width: compact ? 22 : 28,
          height: compact ? 22 : 28,
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
                  _state == PlayerState.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: compact ? 20 : 24,
                  color: minimalUi
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.70)
                      : null,
                ),
                onPressed: _toggle,
                visualDensity: compact
                    ? VisualDensity.compact
                    : VisualDensity.standard,
                padding: compact ? EdgeInsets.zero : null,
                constraints: compact
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
                    onChanged: duration.inMilliseconds <= 0
                        ? null
                        : (value) => _player.seek(
                            Duration(milliseconds: value.round()),
                          ),
                  ),
                ),
              ),
              if (minimalUi && widget.onDownload != null)
                IconButton(
                  tooltip: 'Öppna externt',
                  icon: Icon(
                    Icons.open_in_new_rounded,
                    size: compact ? 18 : 20,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                  onPressed: widget.onDownload,
                  visualDensity: VisualDensity.compact,
                )
              else if (!minimalUi) ...[
                SizedBox(width: compact ? 6 : 8),
                Text(_formatDuration(_position), style: timeStyle),
                Text(' / ', style: timeStyle),
                Text(_formatDuration(duration), style: timeStyle),
              ],
            ],
          ),
          SizedBox(height: compact ? 6 : 10),
          if (minimalUi)
            SliderTheme(
              data: volumeSliderTheme,
              child: Slider(
                min: 0,
                max: 1,
                value: _volume,
                onChanged: _setVolume,
              ),
            )
          else
            Row(
              children: [
                IconButton(
                  icon: Icon(volumeIcon, size: compact ? 18 : 20),
                  onPressed: _toggleMute,
                  visualDensity: compact
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                  padding: compact ? EdgeInsets.zero : null,
                  constraints: compact
                      ? const BoxConstraints(minWidth: 32, minHeight: 32)
                      : null,
                ),
                Expanded(
                  child: SliderTheme(
                    data: volumeSliderTheme,
                    child: Slider(
                      min: 0,
                      max: 1,
                      value: _volume,
                      onChanged: _setVolume,
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
        if (!minimalUi && widget.title != null && widget.title!.isNotEmpty) ...[
          Text(widget.title!, style: titleStyle),
          SizedBox(height: compact ? 8 : 12),
        ],
        playbackBody,
        if (!minimalUi && widget.onDownload != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onDownload,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Öppna externt'),
            ),
          ),
        ],
      ],
    );

    if (minimalUi) {
      return Padding(padding: padding, child: content);
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: compact ? 0 : null,
      color: compact ? Colors.white.withValues(alpha: 0.08) : null,
      shape: cardShape,
      child: Padding(padding: padding, child: content),
    );
  }

  String _formatDuration(Duration duration) {
    String two(int n) => n.toString().padLeft(2, '0');
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = two(minutes);
    final ss = two(seconds);
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }
}
