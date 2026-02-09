import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:aveli/shared/widgets/aveli_video_player.dart';

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _streams =
      <int, StreamController<VideoEvent>>{};
  int _nextPlayerId = 1;
  int playCalls = 0;
  int pauseCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) {
    return createWithOptions(
      VideoCreationOptions(
        dataSource: dataSource,
        viewType: VideoViewType.textureView,
      ),
    );
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final playerId = _nextPlayerId++;
    final stream = StreamController<VideoEvent>();
    _streams[playerId] = stream;
    scheduleMicrotask(() {
      stream.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: const Size(640, 360),
        ),
      );
      stream.add(
        VideoEvent(
          eventType: VideoEventType.isPlayingStateUpdate,
          isPlaying: false,
        ),
      );
    });
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    return _streams[playerId]!.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    await _streams.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async {
    playCalls++;
    _streams[playerId]?.add(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: true,
      ),
    );
  }

  @override
  Future<void> pause(int playerId) async {
    pauseCalls++;
    _streams[playerId]?.add(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: false,
      ),
    );
  }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => const SizedBox.expand();

  @override
  Widget buildViewWithOptions(VideoViewOptions options) {
    return const SizedBox.expand();
  }
}

void main() {
  late VideoPlayerPlatform originalPlatform;

  setUp(() {
    originalPlatform = VideoPlayerPlatform.instance;
  });

  tearDown(() {
    VideoPlayerPlatform.instance = originalPlatform;
  });

  testWidgets('shows placeholder for empty playback url', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AveliVideoPlayer(playbackUrl: '')),
      ),
    );

    expect(find.text('Video saknas'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('surface tap toggles play and pause', (tester) async {
    final fakePlatform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakePlatform;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: AveliVideoPlayer(
              playbackUrl: 'https://cdn.example.com/lesson-video.mp4',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 20; i++) {
      if (find.byIcon(Icons.play_arrow_rounded).evaluate().isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    final playCallsBeforeTap = fakePlatform.playCalls;
    await tester.tap(find.byType(AveliVideoPlayer));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakePlatform.playCalls, playCallsBeforeTap + 1);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    final pauseCallsBeforeTap = fakePlatform.pauseCalls;
    await tester.tap(find.byType(AveliVideoPlayer));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakePlatform.pauseCalls, pauseCallsBeforeTap + 1);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });
}
