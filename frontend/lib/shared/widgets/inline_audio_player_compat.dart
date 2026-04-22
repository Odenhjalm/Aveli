import 'dart:async';

import 'package:flutter/material.dart';

import 'package:aveli/shared/audio/home_audio_engine.dart';

import 'inline_audio_player_contract.dart';
import 'inline_audio_player_view.dart';

class InlineAudioPlayer extends StatefulWidget {
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
    this.engineFactory,
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
  final HomeAudioEngineFactory? engineFactory;

  @override
  State<InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<InlineAudioPlayer> {
  late final HomeAudioEngine _engine;
  late String _activeUrl;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  HomeAudioEnginePlaybackState _playbackState =
      HomeAudioEnginePlaybackState.stopped;
  bool _initializing = true;
  String? _error;
  double _volume = 1.0;
  double _lastVolume = 1.0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _activeUrl = widget.url;
    _engine = (widget.engineFactory ?? createHomeAudioEngine)();
    _engine.setCallbacks(
      HomeAudioEngineCallbacks(
        onDurationChanged: (duration) {
          if (!mounted) {
            return;
          }
          setState(() {
            _duration = duration;
          });
        },
        onPositionChanged: (position) {
          if (!mounted) {
            return;
          }
          setState(() {
            _position = position;
          });
        },
        onPlaybackStateChanged: (playbackState) {
          if (!mounted) {
            return;
          }
          setState(() {
            _playbackState = playbackState;
            _initializing = false;
            if (playbackState == HomeAudioEnginePlaybackState.completed) {
              _position = Duration.zero;
            }
          });
        },
        onEnded: () {
          widget.onEnded?.call();
        },
        onError: _reportPlaybackError,
      ),
    );
    _restoreVolumeState(widget.initialVolumeState, notify: false);
    unawaited(_engine.setVolume(_volume));
    unawaited(_loadUrl(_activeUrl));
  }

  @override
  void didUpdateWidget(covariant InlineAudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _activeUrl = widget.url;
      unawaited(_loadUrl(_activeUrl));
      return;
    }
    if (oldWidget.initialVolumeState != widget.initialVolumeState) {
      _restoreVolumeState(widget.initialVolumeState, notify: false);
    }
  }

  Future<void> _loadUrl(String url) async {
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = null;
        _position = Duration.zero;
        _duration = Duration.zero;
        _playbackState = HomeAudioEnginePlaybackState.stopped;
      });
    }
    try {
      await _engine.setVolume(_volume);
      await _engine.load(url);
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _initializing = false;
        _error = null;
      });
      if (widget.autoPlay) {
        await _engine.play();
      }
    } catch (error) {
      _reportPlaybackError(error.toString());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_engine.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_error != null) {
      return;
    }
    if (_playbackState == HomeAudioEnginePlaybackState.playing) {
      await _engine.pause();
      return;
    }
    await _engine.play();
  }

  Future<void> _seek(Duration position) async {
    setState(() {
      _position = position;
    });
    await _engine.seek(position);
  }

  void _setVolume(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if (clamped > 0) {
      _lastVolume = clamped;
    }
    setState(() {
      _volume = clamped;
    });
    unawaited(_engine.setVolume(clamped));
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
    unawaited(_engine.setVolume(_volume));
    if (!changed) {
      return;
    }
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
    if (!mounted || _disposed) {
      return;
    }
    setState(() {
      _error = message;
      _initializing = false;
      _playbackState = HomeAudioEnginePlaybackState.stopped;
    });
    widget.onError?.call(message);
  }

  @override
  Widget build(BuildContext context) {
    return InlineAudioPlayerView(
      position: _position,
      duration: _duration,
      volume: _volume,
      isPlaying: _playbackState == HomeAudioEnginePlaybackState.playing,
      isInitializing: _initializing,
      errorMessage: _error,
      title: widget.title,
      onDownload: widget.onDownload,
      onTogglePlayPause: _initializing ? null : _toggle,
      onSeek: _initializing ? null : _seek,
      onVolumeChanged: _initializing ? null : _setVolume,
      onToggleMute: _toggleMute,
      compact: widget.compact,
      minimalUi: widget.minimalUi,
      homePlayerUi: widget.homePlayerUi,
    );
  }
}
