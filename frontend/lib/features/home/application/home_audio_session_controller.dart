import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/home/data/home_audio_repository.dart';
import 'package:aveli/shared/audio/home_audio_engine.dart';

typedef HomeAudioItem = HomeAudioFeedItem;

final homeAudioEngineFactoryProvider = Provider<HomeAudioEngineFactory>((ref) {
  return createHomeAudioEngine;
});

class HomeAudioQueueEntry extends Equatable {
  const HomeAudioQueueEntry({
    required this.index,
    required this.sessionKey,
    required this.title,
    required this.resolvedUrl,
    required this.mediaId,
  });

  final int index;
  final String sessionKey;
  final String title;
  final String resolvedUrl;
  final String? mediaId;

  @override
  List<Object?> get props => [index, sessionKey, title, resolvedUrl, mediaId];
}

class HomeAudioSessionState extends Equatable {
  const HomeAudioSessionState({
    this.queue = const <HomeAudioQueueEntry>[],
    this.currentIndex,
    this.playbackWanted = false,
    this.volume = 1.0,
    this.lastNonZeroVolume = 1.0,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.activeEpoch = 0,
    this.handledEndedEpoch = 0,
    this.isPlaying = false,
    this.isInitializing = false,
    this.errorMessage,
  });

  final List<HomeAudioQueueEntry> queue;
  final int? currentIndex;
  final bool playbackWanted;
  final double volume;
  final double lastNonZeroVolume;
  final Duration position;
  final Duration duration;
  final int activeEpoch;
  final int handledEndedEpoch;
  final bool isPlaying;
  final bool isInitializing;
  final String? errorMessage;

  HomeAudioQueueEntry? get currentEntry {
    final index = currentIndex;
    if (index == null || index < 0 || index >= queue.length) {
      return null;
    }
    return queue[index];
  }

  bool get hasQueue => queue.isNotEmpty;

  HomeAudioSessionState copyWith({
    List<HomeAudioQueueEntry>? queue,
    Object? currentIndex = _sentinel,
    bool? playbackWanted,
    double? volume,
    double? lastNonZeroVolume,
    Duration? position,
    Duration? duration,
    int? activeEpoch,
    int? handledEndedEpoch,
    bool? isPlaying,
    bool? isInitializing,
    Object? errorMessage = _sentinel,
  }) {
    return HomeAudioSessionState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex == _sentinel
          ? this.currentIndex
          : currentIndex as int?,
      playbackWanted: playbackWanted ?? this.playbackWanted,
      volume: volume ?? this.volume,
      lastNonZeroVolume: lastNonZeroVolume ?? this.lastNonZeroVolume,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      activeEpoch: activeEpoch ?? this.activeEpoch,
      handledEndedEpoch: handledEndedEpoch ?? this.handledEndedEpoch,
      isPlaying: isPlaying ?? this.isPlaying,
      isInitializing: isInitializing ?? this.isInitializing,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  @override
  List<Object?> get props => [
    queue,
    currentIndex,
    playbackWanted,
    volume,
    lastNonZeroVolume,
    position,
    duration,
    activeEpoch,
    handledEndedEpoch,
    isPlaying,
    isInitializing,
    errorMessage,
  ];
}

class HomeAudioSessionController
    extends AutoDisposeNotifier<HomeAudioSessionState> {
  HomeAudioEngine? _engine;
  bool _disposed = false;
  int _sessionSeed = 0;
  int _completionEligibleEpoch = 0;

  @override
  HomeAudioSessionState build() {
    _engine = ref.read(homeAudioEngineFactoryProvider)();
    _engine!.setCallbacks(
      HomeAudioEngineCallbacks(
        onDurationChanged: _onDurationChanged,
        onPositionChanged: _onPositionChanged,
        onPlaybackStateChanged: _onPlaybackStateChanged,
        onEnded: _onEnded,
        onError: _onError,
      ),
    );
    ref.onDispose(() {
      _disposed = true;
      final engine = _engine;
      _engine = null;
      if (engine != null) {
        unawaited(engine.dispose());
      }
    });
    return const HomeAudioSessionState();
  }

  Future<void> hydrateQueue(List<HomeAudioItem> items) async {
    final nextEntries = _buildQueue(items);
    if (nextEntries.isEmpty) {
      if (!state.hasQueue) {
        state = state.copyWith(currentIndex: null);
      }
      return;
    }
    if (state.hasQueue) {
      return;
    }

    _sessionSeed += 1;
    final queue = List<HomeAudioQueueEntry>.unmodifiable(
      nextEntries.asMap().entries.map(
        (entry) => HomeAudioQueueEntry(
          index: entry.key,
          sessionKey: 'home-audio-$_sessionSeed-${entry.key}',
          title: entry.value.title,
          resolvedUrl: entry.value.resolvedUrl,
          mediaId: entry.value.mediaId,
        ),
      ),
    );
    state = state.copyWith(queue: queue, currentIndex: 0);
    await _loadCurrentIndex();
  }

  Future<void> selectIndex(int index) async {
    if (index < 0 || index >= state.queue.length) {
      return;
    }
    if (state.currentIndex == index) {
      return;
    }
    state = state.copyWith(currentIndex: index);
    await _loadCurrentIndex();
  }

  Future<void> play() async {
    if (!state.hasQueue) {
      return;
    }
    state = state.copyWith(playbackWanted: true, errorMessage: null);
    if (state.isInitializing) {
      return;
    }
    await _engine?.play();
  }

  Future<void> pause() async {
    state = state.copyWith(playbackWanted: false);
    if (state.isInitializing) {
      return;
    }
    await _engine?.pause();
  }

  Future<void> toggle() async {
    if (state.isPlaying) {
      await pause();
      return;
    }
    await play();
  }

  Future<void> seek(Duration position) async {
    if (state.currentEntry == null) {
      return;
    }
    state = state.copyWith(position: position);
    if (position > Duration.zero) {
      _completionEligibleEpoch = state.activeEpoch;
    }
    await _engine?.seek(position);
  }

  Future<void> setVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    final nextLastNonZeroVolume = clamped > 0
        ? clamped
        : (state.lastNonZeroVolume > 0 ? state.lastNonZeroVolume : 1.0);
    state = state.copyWith(
      volume: clamped,
      lastNonZeroVolume: nextLastNonZeroVolume,
    );
    await _engine?.setVolume(clamped);
  }

  Future<void> next() async {
    final index = state.currentIndex;
    if (index == null) {
      return;
    }
    await selectIndex(index + 1);
  }

  Future<void> prev() async {
    final index = state.currentIndex;
    if (index == null) {
      return;
    }
    await selectIndex(index - 1);
  }

  Future<void> _loadCurrentIndex() async {
    final entry = state.currentEntry;
    if (entry == null) {
      return;
    }
    final epoch = state.activeEpoch + 1;
    _completionEligibleEpoch = 0;
    state = state.copyWith(
      activeEpoch: epoch,
      position: Duration.zero,
      duration: Duration.zero,
      isPlaying: false,
      isInitializing: true,
      errorMessage: null,
    );
    try {
      await _engine?.setVolume(state.volume);
      await _engine?.load(entry.resolvedUrl);
      if (_disposed || state.activeEpoch != epoch) {
        return;
      }
      state = state.copyWith(isInitializing: false, errorMessage: null);
      if (state.playbackWanted) {
        await _engine?.play();
      }
    } catch (error) {
      if (_disposed || state.activeEpoch != epoch) {
        return;
      }
      _onError(error.toString());
    }
  }

  List<_QueueSeed> _buildQueue(List<HomeAudioItem> items) {
    return items
        .where((item) => item.isReady)
        .map(
          (item) => _QueueSeed(
            title: item.title,
            resolvedUrl: item.media.resolvedUrl!,
            mediaId: item.media.mediaId,
          ),
        )
        .toList(growable: false);
  }

  void _onDurationChanged(Duration duration) {
    if (_disposed) {
      return;
    }
    state = state.copyWith(duration: duration.abs());
  }

  void _onPositionChanged(Duration position) {
    if (_disposed) {
      return;
    }
    if (!state.isInitializing && position > Duration.zero) {
      _completionEligibleEpoch = state.activeEpoch;
    }
    state = state.copyWith(position: position);
  }

  void _onPlaybackStateChanged(HomeAudioEnginePlaybackState playbackState) {
    if (_disposed) {
      return;
    }
    switch (playbackState) {
      case HomeAudioEnginePlaybackState.playing:
        state = state.copyWith(isPlaying: true, isInitializing: false);
        return;
      case HomeAudioEnginePlaybackState.paused:
      case HomeAudioEnginePlaybackState.stopped:
        state = state.copyWith(isPlaying: false, isInitializing: false);
        return;
      case HomeAudioEnginePlaybackState.completed:
        state = state.copyWith(
          isPlaying: false,
          isInitializing: false,
          position: Duration.zero,
        );
        return;
    }
  }

  void _onEnded() {
    if (_disposed) {
      return;
    }
    final epoch = state.activeEpoch;
    final currentIndex = state.currentIndex;
    if (currentIndex == null) {
      return;
    }
    if (state.isInitializing) {
      return;
    }
    if (_completionEligibleEpoch != epoch) {
      return;
    }
    if (state.handledEndedEpoch == epoch) {
      return;
    }

    state = state.copyWith(
      handledEndedEpoch: epoch,
      isPlaying: false,
      isInitializing: false,
      position: Duration.zero,
    );

    final nextIndex = currentIndex + 1;
    if (nextIndex >= state.queue.length) {
      return;
    }

    unawaited(selectIndex(nextIndex));
  }

  void _onError(String message) {
    if (_disposed) {
      return;
    }
    state = state.copyWith(
      isPlaying: false,
      isInitializing: false,
      errorMessage: message,
    );
  }
}

final homeAudioSessionControllerProvider =
    AutoDisposeNotifierProvider<
      HomeAudioSessionController,
      HomeAudioSessionState
    >(HomeAudioSessionController.new);

class _QueueSeed {
  const _QueueSeed({
    required this.title,
    required this.resolvedUrl,
    required this.mediaId,
  });

  final String title;
  final String resolvedUrl;
  final String? mediaId;
}

const _sentinel = Object();
