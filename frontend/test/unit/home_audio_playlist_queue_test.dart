import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/home/application/home_audio_playlist_queue.dart';

void main() {
  HomeAudioQueueItem playable(String id) =>
      HomeAudioQueueItem(id: id, isPlayable: true);
  HomeAudioQueueItem blocked(String id) =>
      HomeAudioQueueItem(id: id, isPlayable: false);

  test('playNext advances from ended track and skips blocked entries', () {
    final queue = HomeAudioPlaylistQueue();
    queue.setItems([
      playable('track-1'),
      blocked('track-2'),
      playable('track-3'),
    ]);

    queue.playAt(0);
    final next = queue.playNext(auto: true);

    expect(next?.id, 'track-3');
    expect(queue.currentItem?.id, 'track-3');
  });

  test('playNext wraps to first track after reaching the end', () {
    final queue = HomeAudioPlaylistQueue();
    queue.setItems([
      playable('track-1'),
      playable('track-2'),
      playable('track-3'),
    ]);

    queue.playAt(2);
    final wrapped = queue.playNext(auto: true);

    expect(wrapped?.id, 'track-1');
    expect(queue.currentIndex, 0);
  });

  test('failed tracks are skipped and queue stops when all playable fail', () {
    final queue = HomeAudioPlaylistQueue();
    queue.setItems([playable('track-1'), playable('track-2')]);

    queue.playAt(0);
    queue.markCurrentFailed();

    final firstSkip = queue.playNext(auto: true);
    expect(firstSkip?.id, 'track-2');

    queue.markCurrentFailed();
    final noCandidate = queue.playNext(auto: true);

    expect(noCandidate, isNull);
    expect(queue.allPlayableItemsFailed, isTrue);
  });
}
