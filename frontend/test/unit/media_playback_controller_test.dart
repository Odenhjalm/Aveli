import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/media/application/media_playback_controller.dart';

void main() {
  group('MediaPlaybackController', () {
    test(
      'updates title without interrupting playback when mediaId unchanged',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final sub = container.listen(
          mediaPlaybackControllerProvider,
          (previous, next) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);

        final controller = container.read(
          mediaPlaybackControllerProvider.notifier,
        );

        await controller.play(
          mediaId: 'profile-media-id',
          mediaType: MediaPlaybackType.audio,
          url: 'https://example.com/audio.mp3',
          title: 'Before rename',
        );

        final before = container.read(mediaPlaybackControllerProvider);
        expect(before.isPlaying, isTrue);
        expect(before.currentMediaId, equals('profile-media-id'));
        expect(before.url, equals('https://example.com/audio.mp3'));
        expect(before.title, equals('Before rename'));

        await controller.play(
          mediaId: 'profile-media-id',
          mediaType: MediaPlaybackType.audio,
          title: 'After rename',
        );

        final after = container.read(mediaPlaybackControllerProvider);
        expect(after.isPlaying, isTrue);
        expect(after.currentMediaId, equals('profile-media-id'));
        expect(after.url, equals('https://example.com/audio.mp3'));
        expect(after.title, equals('After rename'));
      },
    );
  });
}
