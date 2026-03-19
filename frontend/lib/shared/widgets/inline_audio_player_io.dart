import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/media/application/media_providers.dart';

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

  @override
  ConsumerState<InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends ConsumerState<InlineAudioPlayer> {
  static const Duration _sourceRefreshLeeway = Duration(seconds: 30);

  late final AudioPlayer _player;
  late String _activeUrl;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _state = PlayerState.stopped;
  bool _initializing = true;
  String? _error;
  bool _usingBytes = false;
  Uint8List? _cachedBytes;
  double _volume = 1.0;
  double _lastVolume = 1.0;
  DateTime? _sourceExpiresAt;
  Timer? _sourceRefreshTimer;
  bool _refreshingSource = false;
  bool _didAutoPlay = false;

  @override
  void initState() {
    super.initState();
    _activeUrl = widget.url.trim();
    _sourceExpiresAt = widget.sourceExpiresAt?.toUtc();
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
      _sourceRefreshTimer?.cancel();
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
      _activeUrl = widget.url.trim();
      _sourceExpiresAt = widget.sourceExpiresAt?.toUtc();
      unawaited(_prepare());
      return;
    }
    if (oldWidget.sourceExpiresAt != widget.sourceExpiresAt) {
      _sourceExpiresAt = widget.sourceExpiresAt?.toUtc();
      _scheduleSourceRefresh();
    }
    if (oldWidget.initialVolumeState != widget.initialVolumeState) {
      _restoreVolumeState(widget.initialVolumeState, notify: false);
    }
  }

  Future<void> _prepare() async {
    _sourceRefreshTimer?.cancel();
    _didAutoPlay = false;
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = null;
        _position = Duration.zero;
        _duration = widget.durationHint ?? Duration.zero;
      });
    }
    try {
      await _player.stop();
      await _loadSourceForUrl(_activeUrl);
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = null;
        if (widget.durationHint != null &&
            widget.durationHint!.inMilliseconds > 0 &&
            _duration == Duration.zero) {
          _duration = widget.durationHint!;
        }
      });
      _scheduleSourceRefresh();
      unawaited(_maybeAutoPlay());
    } catch (error) {
      if (!mounted) return;
      _reportPlaybackError(error.toString());
    }
  }

  Future<void> _loadSourceForUrl(String url) async {
    try {
      if (!kIsWeb && Platform.isLinux) {
        await _loadSourceFromBytes(url, originalError: null);
        return;
      }
      await _player.setSourceUrl(url);
      _usingBytes = false;
      _cachedBytes = null;
    } on PlatformException catch (error) {
      await _loadSourceFromBytes(url, originalError: error);
    }
  }

  Future<void> _loadSourceFromBytes(
    String url, {
    required Object? originalError,
  }) async {
    final repo = ref.read(mediaRepositoryProvider);
    final bytes = await repo.cacheMediaBytes(
      cacheKey: url,
      downloadPath: url,
      fileExtension: _extensionFromUrl(url),
    );
    await _player.setSource(BytesSource(bytes));
    _usingBytes = true;
    _cachedBytes = bytes;
    if (originalError == null) return;
    if (!mounted) return;
    setState(() {
      _error = null;
    });
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

  void _scheduleSourceRefresh() {
    _sourceRefreshTimer?.cancel();
    final loader = widget.sourceLoader;
    final expiresAt = _sourceExpiresAt;
    if (loader == null || expiresAt == null) return;
    final delay = expiresAt
        .subtract(_sourceRefreshLeeway)
        .difference(DateTime.now().toUtc());
    if (delay <= Duration.zero) {
      unawaited(_refreshPlaybackSource());
      return;
    }
    _sourceRefreshTimer = Timer(delay, () {
      unawaited(_refreshPlaybackSource());
    });
  }

  Future<bool> _refreshPlaybackSource() async {
    final loader = widget.sourceLoader;
    if (loader == null || _refreshingSource) return false;
    _refreshingSource = true;
    final resumePosition = _position;
    final shouldResume = _state == PlayerState.playing;
    try {
      final nextSource = await loader();
      if (!mounted) return false;
      final nextUrl = nextSource.url.trim();
      if (nextUrl.isEmpty) {
        throw StateError('Empty playback URL');
      }
      _sourceExpiresAt = nextSource.expiresAt?.toUtc();
      if (nextUrl == _activeUrl) {
        _scheduleSourceRefresh();
        return true;
      }
      await _player.stop();
      await _loadSourceForUrl(nextUrl);
      _activeUrl = nextUrl;
      await _player.setVolume(_volume);
      if (resumePosition > Duration.zero) {
        await _player.seek(resumePosition);
      }
      if (shouldResume) {
        await _player.resume();
      }
      if (!mounted) return false;
      setState(() {
        _position = resumePosition;
        _error = null;
        _initializing = false;
      });
      _scheduleSourceRefresh();
      return true;
    } catch (_) {
      if (!mounted) return false;
      _sourceRefreshTimer?.cancel();
      _sourceRefreshTimer = Timer(const Duration(seconds: 5), () {
        unawaited(_refreshPlaybackSource());
      });
      return false;
    } finally {
      _refreshingSource = false;
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
    _sourceRefreshTimer?.cancel();
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
        if (_usingBytes && _cachedBytes != null) {
          await _player.play(BytesSource(_cachedBytes!));
        } else {
          await _player.play(UrlSource(_activeUrl));
        }
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
    final restored = state ?? const InlineAudioPlayerVolumeState();
    final nextVolume = restored.volume.clamp(0.0, 1.0).toDouble();
    final nextLastVolume = restored.lastVolume.clamp(0.0, 1.0).toDouble();
    final normalizedLastVolume = nextLastVolume > 0
        ? nextLastVolume
        : (nextVolume > 0 ? nextVolume : 1.0);
    final changed =
        _volume != nextVolume || _lastVolume != normalizedLastVolume;
    _volume = nextVolume;
    _lastVolume = normalizedLastVolume;
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
    _sourceRefreshTimer?.cancel();
    setState(() {
      _error = message;
      _initializing = false;
    });
    widget.onError?.call(message);
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
            'Media saknas eller stöds inte längre',
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
