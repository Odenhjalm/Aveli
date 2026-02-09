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
      expect(find.text('Spela video'), findsOneWidget);

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
      expect(player.controlChrome, InlineVideoControlChrome.playPauseAndStop);
    },
  );
}
