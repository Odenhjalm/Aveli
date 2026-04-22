import 'package:flutter/foundation.dart';

enum HomeAudioEnginePlaybackState { stopped, playing, paused, completed }

@immutable
class HomeAudioEngineCallbacks {
  const HomeAudioEngineCallbacks({
    this.onDurationChanged,
    this.onPositionChanged,
    this.onPlaybackStateChanged,
    this.onEnded,
    this.onError,
  });

  final ValueChanged<Duration>? onDurationChanged;
  final ValueChanged<Duration>? onPositionChanged;
  final ValueChanged<HomeAudioEnginePlaybackState>? onPlaybackStateChanged;
  final VoidCallback? onEnded;
  final ValueChanged<String>? onError;
}

abstract class HomeAudioEngine {
  void setCallbacks(HomeAudioEngineCallbacks callbacks);

  Future<void> load(String url);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> setVolume(double value);

  Future<void> dispose();
}

typedef HomeAudioEngineFactory = HomeAudioEngine Function();
