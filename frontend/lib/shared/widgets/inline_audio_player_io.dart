import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/features/media/application/media_providers.dart';

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
  late final AudioPlayer _player;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _state = PlayerState.stopped;
  bool _initializing = true;
  String? _error;
  bool _usingBytes = false;
  Uint8List? _cachedBytes;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.setReleaseMode(ReleaseMode.stop);
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
    });

    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      if (!kIsWeb && Platform.isLinux) {
        await _prepareFromBytes(null);
        return;
      }
      await _player.setSourceUrl(widget.url);
      if (!mounted) return;
      setState(() {
        _initializing = false;
        if (widget.durationHint != null &&
            widget.durationHint!.inMilliseconds > 0 &&
            _duration == Duration.zero) {
          _duration = widget.durationHint!;
        }
      });
    } on PlatformException catch (error) {
      await _prepareFromBytes(error);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _prepareFromBytes(Object? originalError) async {
    try {
      final repo = ref.read(mediaRepositoryProvider);
      final bytes = await repo.cacheMediaBytes(
        cacheKey: widget.url,
        downloadPath: widget.url,
        fileExtension: _extensionFromUrl(widget.url),
      );
      await _player.setSource(BytesSource(bytes));
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = null;
        _usingBytes = true;
        _cachedBytes = bytes;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        final original = originalError?.toString() ?? '';
        _error = original.isEmpty
            ? error.toString()
            : '$original / ${error.toString()}';
      });
    }
  }

  String? _extensionFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path ?? url;
    final index = path.lastIndexOf('.');
    if (index <= 0 || index == path.length - 1) return null;
    final ext = path.substring(index + 1).toLowerCase();
    return ext.isEmpty ? null : ext;
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_error != null) return;
    if (_state == PlayerState.playing) {
      await _player.pause();
    } else if (_state == PlayerState.paused && _position > Duration.zero) {
      await _player.resume();
    } else {
      if (_usingBytes && _cachedBytes != null) {
        await _player.play(BytesSource(_cachedBytes!));
      } else {
        await _player.play(UrlSource(widget.url));
      }
    }
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
                          _state == PlayerState.playing
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
                              : (value) => _player.seek(
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
