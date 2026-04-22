// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html';

import 'home_audio_engine_contract.dart';

class HomeAudioEngineWeb implements HomeAudioEngine {
  HomeAudioEngineWeb()
    : _audio = AudioElement()
        ..preload = 'auto'
        ..controls = false
        ..loop = false
        ..volume = 1.0,
      _callbacks = const HomeAudioEngineCallbacks() {
    _loadedMetadataSub = _audio.onLoadedMetadata.listen((event) {
      final rawDuration = _audio.duration;
      if (!rawDuration.isFinite || rawDuration <= 0) {
        return;
      }
      _callbacks.onDurationChanged?.call(
        Duration(milliseconds: (rawDuration * 1000).round()).abs(),
      );
    });
    _timeUpdateSub = _audio.onTimeUpdate.listen((event) {
      _callbacks.onPositionChanged?.call(
        Duration(milliseconds: (_audio.currentTime * 1000).round()),
      );
      final rawDuration = _audio.duration;
      if (!rawDuration.isFinite || rawDuration <= 0) {
        return;
      }
      _callbacks.onDurationChanged?.call(
        Duration(milliseconds: (rawDuration * 1000).round()).abs(),
      );
    });
    _playSub = _audio.onPlay.listen((event) {
      _callbacks.onPlaybackStateChanged?.call(
        HomeAudioEnginePlaybackState.playing,
      );
    });
    _pauseSub = _audio.onPause.listen((event) {
      _callbacks.onPlaybackStateChanged?.call(
        HomeAudioEnginePlaybackState.paused,
      );
    });
    _endedSub = _audio.onEnded.listen((event) {
      _callbacks.onPlaybackStateChanged?.call(
        HomeAudioEnginePlaybackState.completed,
      );
      _callbacks.onEnded?.call();
    });
    _errorSub = _audio.onError.listen((event) {
      _callbacks.onError?.call(_currentErrorMessage());
    });
  }

  final AudioElement _audio;
  HomeAudioEngineCallbacks _callbacks;
  late final StreamSubscription<Event> _timeUpdateSub;
  late final StreamSubscription<Event> _loadedMetadataSub;
  late final StreamSubscription<Event> _playSub;
  late final StreamSubscription<Event> _pauseSub;
  late final StreamSubscription<Event> _endedSub;
  late final StreamSubscription<Event> _errorSub;

  @override
  void setCallbacks(HomeAudioEngineCallbacks callbacks) {
    _callbacks = callbacks;
  }

  @override
  Future<void> load(String url) async {
    _audio.pause();
    _audio.src = url;
    _audio.load();
  }

  @override
  Future<void> play() async {
    try {
      await _audio.play();
    } catch (error) {
      _callbacks.onError?.call(error.toString());
    }
  }

  @override
  Future<void> pause() async {
    _audio.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    _audio.currentTime = position.inMilliseconds / 1000;
    _callbacks.onPositionChanged?.call(position);
  }

  @override
  Future<void> setVolume(double value) async {
    _audio.volume = value.clamp(0.0, 1.0).toDouble();
  }

  @override
  Future<void> dispose() async {
    await _timeUpdateSub.cancel();
    await _loadedMetadataSub.cancel();
    await _playSub.cancel();
    await _pauseSub.cancel();
    await _endedSub.cancel();
    await _errorSub.cancel();
    _audio.pause();
    _audio.src = '';
    _audio.load();
  }

  String _currentErrorMessage() {
    final mediaError = _audio.error;
    return switch (mediaError?.code) {
      MediaError.MEDIA_ERR_ABORTED => 'Uppspelningen avbröts.',
      MediaError.MEDIA_ERR_NETWORK => 'Nätverksfel vid uppspelning.',
      MediaError.MEDIA_ERR_DECODE => 'Avkodningsfel, filen kan vara korrupt.',
      MediaError.MEDIA_ERR_SRC_NOT_SUPPORTED =>
        'Formatet stöds inte i denna webbläsare.',
      _ => 'Okänt uppspelningsfel.',
    };
  }
}

HomeAudioEngine createHomeAudioEngine() => HomeAudioEngineWeb();
