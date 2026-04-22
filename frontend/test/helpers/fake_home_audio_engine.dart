import 'package:aveli/shared/audio/home_audio_engine.dart';

class FakeHomeAudioEngineFactory {
  int createCount = 0;
  final List<FakeHomeAudioEngine> engines = <FakeHomeAudioEngine>[];

  HomeAudioEngine create() {
    createCount += 1;
    final engine = FakeHomeAudioEngine(label: 'engine-$createCount');
    engines.add(engine);
    return engine;
  }

  FakeHomeAudioEngine get latest => engines.last;

  FakeHomeAudioEngine get single => engines.single;
}

class FakeHomeAudioEngine implements HomeAudioEngine {
  FakeHomeAudioEngine({required this.label});

  final String label;
  HomeAudioEngineCallbacks _callbacks = const HomeAudioEngineCallbacks();
  final List<String> loadedUrls = <String>[];
  final List<double> volumeHistory = <double>[];
  final List<Duration> seekHistory = <Duration>[];
  int playCalls = 0;
  int pauseCalls = 0;
  int disposeCalls = 0;
  HomeAudioEnginePlaybackState playbackState =
      HomeAudioEnginePlaybackState.stopped;
  Duration currentPosition = Duration.zero;
  Duration currentDuration = const Duration(minutes: 3);

  @override
  void setCallbacks(HomeAudioEngineCallbacks callbacks) {
    _callbacks = callbacks;
  }

  @override
  Future<void> load(String url) async {
    loadedUrls.add(url);
    currentPosition = Duration.zero;
    playbackState = HomeAudioEnginePlaybackState.stopped;
    _callbacks.onPositionChanged?.call(currentPosition);
    _callbacks.onDurationChanged?.call(currentDuration);
    _callbacks.onPlaybackStateChanged?.call(playbackState);
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    playbackState = HomeAudioEnginePlaybackState.playing;
    _callbacks.onPlaybackStateChanged?.call(playbackState);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    playbackState = HomeAudioEnginePlaybackState.paused;
    _callbacks.onPlaybackStateChanged?.call(playbackState);
  }

  @override
  Future<void> seek(Duration position) async {
    seekHistory.add(position);
    currentPosition = position;
    _callbacks.onPositionChanged?.call(position);
  }

  @override
  Future<void> setVolume(double value) async {
    volumeHistory.add(value);
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }

  void emitProgress(Duration position) {
    currentPosition = position;
    _callbacks.onPositionChanged?.call(position);
  }

  void emitDuration(Duration duration) {
    currentDuration = duration;
    _callbacks.onDurationChanged?.call(duration);
  }

  void emitEnded() {
    playbackState = HomeAudioEnginePlaybackState.completed;
    currentPosition = Duration.zero;
    _callbacks.onPlaybackStateChanged?.call(playbackState);
    _callbacks.onEnded?.call();
  }
}
