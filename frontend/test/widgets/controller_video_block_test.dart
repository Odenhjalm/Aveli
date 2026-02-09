import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/media/application/media_playback_controller.dart';
import 'package:aveli/features/media/presentation/controller_video_block.dart';
import 'package:aveli/shared/widgets/media_player.dart';

void main() {
  testWidgets(
    'controller block activates playback only after explicit surface tap',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: ControllerVideoBlock(
                mediaId: 'lesson-video-1',
                url: 'https://cdn.example.com/lesson-1.mp4',
                title: 'Lektion 1',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(InlineVideoPlayer), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      await tester.tap(find.byType(VideoSurfaceTapTarget));
      await tester.pump();

      final playback = container.read(mediaPlaybackControllerProvider);
      expect(playback.currentMediaId, 'lesson-video-1');
      expect(playback.mediaType, MediaPlaybackType.video);
      expect(playback.isPlaying, isTrue);
      expect(playback.isPaused, isFalse);
      expect(find.byType(InlineVideoPlayer), findsOneWidget);
      final player = tester.widget<InlineVideoPlayer>(
        find.byType(InlineVideoPlayer),
      );
      expect(player.playback.controlsMode, InlineVideoControlsMode.lesson);
      expect(
        player.playback.controlChrome,
        InlineVideoControlChrome.playPauseAndStop,
      );
    },
  );

  testWidgets('controller block can opt into home control mode', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: ControllerVideoBlock(
              mediaId: 'home-video-1',
              url: 'https://cdn.example.com/home-1.mp4',
              title: 'Hemvideo',
              controlsMode: InlineVideoControlsMode.home,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(VideoSurfaceTapTarget));
    await tester.pump();

    final player = tester.widget<InlineVideoPlayer>(
      find.byType(InlineVideoPlayer),
    );
    expect(player.playback.controlsMode, InlineVideoControlsMode.home);
  });

  testWidgets('controller block prefers playbackUrlLoader on play', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var loaderCalls = 0;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ControllerVideoBlock(
              mediaId: 'lesson-video-loader',
              url: '/studio/media/legacy-path',
              playbackUrlLoader: () async {
                loaderCalls++;
                return 'https://cdn.example.com/lesson-loader.mp4';
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(VideoSurfaceTapTarget));
    await tester.pump();
    await tester.pump();

    final playback = container.read(mediaPlaybackControllerProvider);
    expect(loaderCalls, 1);
    expect(playback.currentMediaId, 'lesson-video-loader');
    expect(playback.url, 'https://cdn.example.com/lesson-loader.mp4');
    expect(find.byType(InlineVideoPlayer), findsOneWidget);
  });
}
