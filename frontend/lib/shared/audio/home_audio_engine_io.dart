import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'home_audio_engine_contract.dart';

class HomeAudioEngineIO implements HomeAudioEngine {
  HomeAudioEngineIO()
    : _player = AudioPlayer(),
      _callbacks = const HomeAudioEngineCallbacks() {
    _player.setReleaseMode(ReleaseMode.stop);
    _durationSub = _player.onDurationChanged.listen((duration) {
      _callbacks.onDurationChanged?.call(duration);
    });
    _positionSub = _player.onPositionChanged.listen((position) {
      _position = position;
      _callbacks.onPositionChanged?.call(position);
    });
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      _callbacks.onPlaybackStateChanged?.call(_mapPlaybackState(state));
    });
    _completeSub = _player.onPlayerComplete.listen((event) {
      _position = Duration.zero;
      _callbacks.onPlaybackStateChanged?.call(
        HomeAudioEnginePlaybackState.completed,
      );
      _callbacks.onEnded?.call();
    });
  }

  final AudioPlayer _player;
  HomeAudioEngineCallbacks _callbacks;
  late final StreamSubscription<Duration> _durationSub;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<PlayerState> _stateSub;
  late final StreamSubscription<void> _completeSub;
  String _activeUrl = '';
  Duration _position = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;

  @override
  void setCallbacks(HomeAudioEngineCallbacks callbacks) {
    _callbacks = callbacks;
  }

  @override
  Future<void> load(String url) async {
    _activeUrl = url;
    _position = Duration.zero;
    _playerState = PlayerState.stopped;
    await _player.stop();
    await _player.setSourceUrl(url);
  }

  @override
  Future<void> play() async {
    if (_activeUrl.isEmpty) {
      return;
    }
    try {
      if (_playerState == PlayerState.playing) {
        return;
      }
      if (_playerState == PlayerState.paused && _position > Duration.zero) {
        await _player.resume();
      } else {
        await _player.play(UrlSource(_activeUrl));
      }
    } catch (error) {
      _callbacks.onError?.call(error.toString());
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (error) {
      _callbacks.onError?.call(error.toString());
    }
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    try {
      await _player.seek(position);
    } catch (error) {
      _callbacks.onError?.call(error.toString());
    }
  }

  @override
  Future<void> setVolume(double value) async {
    try {
      await _player.setVolume(value.clamp(0.0, 1.0).toDouble());
    } catch (error) {
      _callbacks.onError?.call(error.toString());
    }
  }

  @override
  Future<void> dispose() async {
    await _durationSub.cancel();
    await _positionSub.cancel();
    await _stateSub.cancel();
    await _completeSub.cancel();
    await _player.dispose();
  }

  HomeAudioEnginePlaybackState _mapPlaybackState(PlayerState state) {
    _playerState = state;
    return switch (state) {
      PlayerState.playing => HomeAudioEnginePlaybackState.playing,
      PlayerState.paused => HomeAudioEnginePlaybackState.paused,
      PlayerState.completed => HomeAudioEnginePlaybackState.completed,
      PlayerState.stopped => HomeAudioEnginePlaybackState.stopped,
      PlayerState.disposed => HomeAudioEnginePlaybackState.stopped,
    };
  }
}

HomeAudioEngine createHomeAudioEngine() => HomeAudioEngineIO();
