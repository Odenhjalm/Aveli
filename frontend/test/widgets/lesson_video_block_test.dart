import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:aveli/features/media/presentation/controller_video_block.dart';
import 'package:aveli/shared/widgets/aveli_video_player.dart';
import 'package:aveli/shared/widgets/lesson_video_block.dart';

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

Finder _legacyInlineVideoPlayerFinder() {
  return find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == 'InlineVideoPlayer',
    description: 'InlineVideoPlayer',
  );
}

void main() {
  const sampleUrl = 'https://cdn.example.com/lesson.mp4';
  const invalidUrl = 'ftp://cdn.example.com/lesson.mp4';
  const containerKey = Key('test_lesson_video_block_container');
  const surfaceKey = Key('test_lesson_video_block_surface');
  const playerKey = Key('test_lesson_video_block_player');
  late VideoPlayerPlatform originalPlatform;

  setUp(() {
    originalPlatform = VideoPlayerPlatform.instance;
  });

  tearDown(() {
    VideoPlayerPlatform.instance = originalPlatform;
  });

  testWidgets('renders AveliVideoPlayer for valid URL with no legacy players', (
    tester,
  ) async {
    final fakePlatform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakePlatform;
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1280,
              child: LessonVideoBlock(
                url: sampleUrl,
                title: 'Demo',
                containerKey: containerKey,
                surfaceKey: surfaceKey,
                playerKey: playerKey,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byKey(containerKey), findsOneWidget);
    expect(find.byKey(surfaceKey), findsOneWidget);
    expect(find.byType(AveliVideoPlayer), findsOneWidget);
    expect(_legacyInlineVideoPlayerFinder(), findsNothing);
    expect(find.byType(ControllerVideoBlock), findsNothing);

    final size = tester.getSize(find.byKey(containerKey));
    expect(size.width, lessThanOrEqualTo(920));
    expect(size.width, greaterThan(880));
  });

  testWidgets('video block stays between text nodes instead of inline flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ovanför'),
                LessonVideoBlock(
                  url: sampleUrl,
                  containerKey: containerKey,
                  surfaceKey: surfaceKey,
                  playerKey: playerKey,
                ),
                Text('Nedanför'),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final topTextBottom = tester.getBottomLeft(find.text('Ovanför')).dy;
    final blockTop = tester.getTopLeft(find.byKey(containerKey)).dy;
    final blockBottom = tester.getBottomLeft(find.byKey(containerKey)).dy;
    final bottomTextTop = tester.getTopLeft(find.text('Nedanför')).dy;

    expect(blockTop, greaterThan(topTextBottom));
    expect(bottomTextTop, greaterThan(blockBottom));
  });

  testWidgets('video block semantics expose editor accessibility labels', (
    tester,
  ) async {
    final fakePlatform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakePlatform;
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LessonVideoBlock(
              url: sampleUrl,
              containerKey: containerKey,
              surfaceKey: surfaceKey,
              playerKey: playerKey,
              semanticLabel: 'Videoblock i lektionseditorn',
              semanticHint: 'Aktivera med Enter eller mellanslag.',
            ),
          ),
        ),
      );

      await tester.pump();

      final semanticsNode = tester.getSemantics(find.byKey(surfaceKey));
      expect(semanticsNode.label, contains('Videoblock i lektionseditorn'));
      expect(
        semanticsNode.hint,
        contains('Aktivera med Enter eller mellanslag.'),
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('invalid URL renders placeholder without mounting player', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LessonVideoBlock(
            url: invalidUrl,
            containerKey: containerKey,
            surfaceKey: surfaceKey,
            playerKey: playerKey,
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(AveliVideoPlayer), findsNothing);
    expect(_legacyInlineVideoPlayerFinder(), findsNothing);
    expect(find.byType(ControllerVideoBlock), findsNothing);
    expect(find.text('Video saknas eller stöds inte längre'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders multiple lesson blocks without shared key collisions', (
    tester,
  ) async {
    final fakePlatform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakePlatform;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              LessonVideoBlock(url: 'https://cdn.example.com/one.mp4'),
              LessonVideoBlock(url: 'https://cdn.example.com/two.mp4'),
            ],
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(LessonVideoBlock), findsNWidgets(2));
    expect(find.byType(AveliVideoPlayer), findsNWidgets(2));
    expect(_legacyInlineVideoPlayerFinder(), findsNothing);
    expect(find.byType(ControllerVideoBlock), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
