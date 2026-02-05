import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/media/application/media_providers.dart';

class InlineAudioPlayer extends ConsumerStatefulWidget {
  const InlineAudioPlayer({
    super.key,
    required this.url,
    this.title,
    this.onDownload,
    this.durationHint,
    this.compact = false,
    this.autoPlay = false,
    this.minimalUi = false,
  });

  final String url;
  final String? title;
  final Future<void> Function()? onDownload;
  final Duration? durationHint;
  final bool compact;
  final bool autoPlay;
  final bool minimalUi;

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
  double _volume = 1.0;
  double _lastVolume = 1.0;
  bool _didAutoPlay = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.setReleaseMode(ReleaseMode.stop);
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
      unawaited(_maybeAutoPlay());
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
      unawaited(_maybeAutoPlay());
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

  Future<void> _maybeAutoPlay() async {
    if (!mounted) return;
    if (!widget.autoPlay) return;
    if (_didAutoPlay) return;
    if (_error != null) return;
    _didAutoPlay = true;
    try {
      await _toggle();
    } catch (_) {
      // Ignore auto-play failures (e.g. platform restrictions).
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

  void _setVolume(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if (clamped > 0) {
      _lastVolume = clamped;
    }
    setState(() => _volume = clamped);
    unawaited(_player.setVolume(clamped));
  }

  void _toggleMute() {
    final next = _volume > 0 ? 0.0 : (_lastVolume > 0 ? _lastVolume : 1.0);
    _setVolume(next);
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
    final minimalUi = widget.minimalUi;
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
    final padding = minimalUi
        ? EdgeInsets.zero
        : compact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
        : const EdgeInsets.all(16);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!minimalUi && (widget.title ?? '').isNotEmpty) ...[
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
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
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
          ),
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
