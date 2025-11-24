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
  });

  final String url;
  final String? title;
  final Future<void> Function()? onDownload;
  final Duration? durationHint;

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
  StreamSubscription<Event>? _timeUpdateSub;
  StreamSubscription<Event>? _loadedMetadataSub;
  StreamSubscription<Event>? _playSub;
  StreamSubscription<Event>? _pauseSub;
  StreamSubscription<Event>? _endedSub;
  StreamSubscription<Event>? _errorSub;

  @override
  void initState() {
    super.initState();
    _audio = AudioElement()
      ..preload = 'auto'
      ..controls = false
      ..loop = false;
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
        });
      } else {
        setState(() {
          _initializing = false;
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
    final duration = _effectiveDuration;
    final maxMillis = max(1, duration.inMilliseconds);
    final position = _position.inMilliseconds.clamp(0, maxMillis);
    final sliderValue = position.toDouble();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((widget.title ?? '').isNotEmpty) ...[
              Text(
                widget.title!,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
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
                        ),
                        onPressed: _toggle,
                      ),
                      Expanded(
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
                      const SizedBox(width: 8),
                      Text(_formatDuration(_position)),
                      const Text(' / '),
                      Text(_formatDuration(duration)),
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
