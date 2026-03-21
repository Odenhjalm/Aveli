import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/home/data/home_audio_repository.dart';

void main() {
  test('fromJson parses the runtime-media playback contract', () {
    final item = HomeAudioItem.fromJson({
      'id': 'runtime-row-1',
      'lesson_id': 'lesson-1',
      'lesson_title': 'Track 1',
      'course_id': 'course-1',
      'course_title': 'Course 1',
      'kind': 'audio',
      'content_type': 'audio/mpeg',
      'duration_seconds': 123,
      'runtime_media_id': 'runtime-media-1',
      'is_playable': true,
      'playback_state': 'ready',
      'failure_reason': 'ok_ready_asset',
    });

    expect(item.id, 'runtime-row-1');
    expect(item.runtimeMediaId, 'runtime-media-1');
    expect(item.isPlayable, isTrue);
    expect(item.playbackState, 'ready');
    expect(item.failureReason, 'ok_ready_asset');
    expect(item.kind, 'audio');
    expect(item.contentType, 'audio/mpeg');
    expect(item.durationSeconds, 123);
  });

  test(
    'displayTitle falls back to originalName when lesson title is blank',
    () {
      final item = HomeAudioItem.fromJson({
        'id': 'runtime-row-2',
        'lesson_id': 'lesson-2',
        'lesson_title': '   ',
        'course_id': 'course-1',
        'course_title': 'Course 1',
        'kind': 'audio',
        'original_name': 'fallback-title.mp3',
        'runtime_media_id': 'runtime-media-2',
        'is_playable': false,
        'playback_state': 'processing',
        'failure_reason': 'asset_not_ready',
      });

      expect(item.displayTitle, 'fallback-title.mp3');
      expect(item.isPlayable, isFalse);
      expect(item.playbackState, 'processing');
    },
  );
}
