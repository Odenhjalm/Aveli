import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/media/application/media_playback_controller.dart';

void main() {
  test('video playback controller tracks paused and resumed states', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(mediaPlaybackControllerProvider.notifier);

    await controller.play(
      mediaId: 'video-1',
      mediaType: MediaPlaybackType.video,
      url: 'https://cdn.example.com/video-1.mp4',
      title: 'Video 1',
    );

    var state = container.read(mediaPlaybackControllerProvider);
    expect(state.currentMediaId, 'video-1');
    expect(state.isPlaying, isTrue);
    expect(state.isPaused, isFalse);

    controller.pause('video-1');
    state = container.read(mediaPlaybackControllerProvider);
    expect(state.currentMediaId, 'video-1');
    expect(state.isPlaying, isTrue);
    expect(state.isPaused, isTrue);

    controller.resume('video-1');
    state = container.read(mediaPlaybackControllerProvider);
    expect(state.currentMediaId, 'video-1');
    expect(state.isPlaying, isTrue);
    expect(state.isPaused, isFalse);

    controller.stop();
    state = container.read(mediaPlaybackControllerProvider);
    expect(state.currentMediaId, isNull);
    expect(state.isPlaying, isFalse);
    expect(state.isPaused, isFalse);
  });
}
