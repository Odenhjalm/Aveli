// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class InlineAudioPlayer extends ConsumerStatefulWidget {
  const InlineAudioPlayer({
    super.key,
    required this.url,
    this.title,
    this.onDownload,
    this.durationHint,
    this.compact = false,
    this.autoPlay = false,
  });

  final String url;
  final String? title;
  final Future<void> Function()? onDownload;
  final Duration? durationHint;
  final bool compact;
  final bool autoPlay;

  @override
  ConsumerState<InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends ConsumerState<InlineAudioPlayer> {
  late AudioElement _audio;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _initializing = true;
  bool _isPlaying = false;
  String? _error;
  double _volume = 1.0;
  double _lastVolume = 1.0;
  StreamSubscription<Event>? _timeUpdateSub;
  StreamSubscription<Event>? _loadedMetadataSub;
  StreamSubscription<Event>? _playSub;
  StreamSubscription<Event>? _pauseSub;
  StreamSubscription<Event>? _endedSub;
  StreamSubscription<Event>? _errorSub;
  bool _didAutoPlay = false;

  @override
  void initState() {
    super.initState();
    _audio = AudioElement()
      ..preload = 'auto'
      ..controls = false
      ..loop = false
      ..volume = _volume;
    _duration = widget.durationHint ?? Duration.zero;
    _attachListeners();
    _setSource(widget.url);
  }

  @override
  void didUpdateWidget(covariant InlineAudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _setSource(widget.url);
    }
  }

  void _attachListeners() {
    _loadedMetadataSub = _audio.onLoadedMetadata.listen((event) {
      if (!mounted) return;
      final rawDuration = _audio.duration;
      if (rawDuration.isFinite && rawDuration > 0) {
        setState(() {
          _duration = Duration(
            milliseconds: (rawDuration * 1000).round(),
          ).abs();
          _initializing = false;
          _error = null;
        });
      } else {
        setState(() {
          _initializing = false;
          _error = null;
        });
      }
    });
    _timeUpdateSub = _audio.onTimeUpdate.listen((event) {
      if (!mounted) return;
      final newPosition = Duration(
        milliseconds: (_audio.currentTime * 1000).round(),
      );
      final rawDuration = _audio.duration;
      setState(() {
        _position = newPosition;
        if ((_duration == Duration.zero || _duration.inMilliseconds <= 0) &&
            rawDuration.isFinite &&
            rawDuration > 0) {
          _duration = Duration(
            milliseconds: (rawDuration * 1000).round(),
          ).abs();
        }
      });
    });
    _playSub = _audio.onPlay.listen((event) {
      if (!mounted) return;
      setState(() {
        _isPlaying = true;
        _initializing = false;
        _error = null;
      });
    });
    _pauseSub = _audio.onPause.listen((event) {
      if (!mounted) return;
      setState(() => _isPlaying = false);
    });
    _endedSub = _audio.onEnded.listen((event) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
    });
    _errorSub = _audio.onError.listen((event) {
      if (!mounted) return;
      final mediaError = _audio.error;
      final message = switch (mediaError?.code) {
        MediaError.MEDIA_ERR_ABORTED => 'Uppspelningen avbröts.',
        MediaError.MEDIA_ERR_NETWORK => 'Nätverksfel vid uppspelning.',
        MediaError.MEDIA_ERR_DECODE => 'Avkodningsfel, filen kan vara korrupt.',
        MediaError.MEDIA_ERR_SRC_NOT_SUPPORTED =>
          'Formatet stöds inte i denna webbläsare.',
        _ => 'Okänt uppspelningsfel.',
      };
      setState(() {
        _initializing = false;
        _error = message;
      });
    });
  }

  void _setSource(String url) {
    setState(() {
      _initializing = true;
      _error = null;
      _isPlaying = false;
      _position = Duration.zero;
    });
    _audio.pause();
    _audio.src = url;
    _audio.load();
    _didAutoPlay = false;
    if (widget.autoPlay) {
      unawaited(_attemptAutoPlay());
    }
  }

  @override
  void dispose() {
    _timeUpdateSub?.cancel();
    _loadedMetadataSub?.cancel();
    _playSub?.cancel();
    _pauseSub?.cancel();
    _endedSub?.cancel();
    _errorSub?.cancel();
    _audio.pause();
    _audio.src = '';
    _audio.load();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_error != null) return;
    try {
      if (_isPlaying) {
        _audio.pause();
      } else {
        await _audio.play();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _initializing = false;
      });
    }
  }

  Future<void> _attemptAutoPlay() async {
    if (!mounted) return;
    if (_didAutoPlay) return;
    if (_error != null) return;
    _didAutoPlay = true;
    try {
      await _audio.play();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _initializing = false;
      });
    }
  }

  void _setVolume(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if (clamped > 0) {
      _lastVolume = clamped;
    }
    setState(() => _volume = clamped);
    _audio.volume = clamped;
  }

  void _toggleMute() {
    final next = _volume > 0 ? 0.0 : (_lastVolume > 0 ? _lastVolume : 1.0);
    _setVolume(next);
  }

  void _seek(Duration target) {
    _audio.currentTime = target.inMilliseconds / 1000;
    setState(() {
      _position = target;
    });
  }

  Duration get _effectiveDuration {
    if (_duration.inMilliseconds > 0) {
      return _duration;
    }
    return widget.durationHint ?? Duration.zero;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.compact;
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
    final sliderTheme = compact
        ? theme.sliderTheme.copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          )
        : theme.sliderTheme;
    final volumeSliderTheme = sliderTheme.copyWith(
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: compact ? 5 : 6),
      overlayShape: RoundSliderOverlayShape(overlayRadius: compact ? 8 : 10),
    );
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
        : const EdgeInsets.all(16);

    return Card(
      margin: EdgeInsets.zero,
      elevation: compact ? 0 : null,
      color: compact ? Colors.white.withValues(alpha: 0.08) : null,
      shape: cardShape,
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((widget.title ?? '').isNotEmpty) ...[
              Text(widget.title!, style: titleStyle),
              SizedBox(height: compact ? 8 : 12),
            ],
            if (_initializing)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(
                'Kunde inte spela upp ljudet: $_error',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              )
            else
              Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: compact ? 20 : 24,
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
                                : (value) => _seek(
                                    Duration(milliseconds: value.round()),
                                  ),
                          ),
                        ),
                      ),
                      SizedBox(width: compact ? 6 : 8),
                      Text(_formatDuration(_position), style: timeStyle),
                      Text(' / ', style: timeStyle),
                      Text(_formatDuration(duration), style: timeStyle),
                    ],
                  ),
                  SizedBox(height: compact ? 6 : 10),
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
              ),
            if (widget.onDownload != null) ...[
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
        ),
      ),
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
