import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/home/data/home_audio_repository.dart';

HomeAudioItem _buildItem({
  String? downloadUrl,
  String? signedUrl,
  DateTime? signedUrlExpiresAt,
}) {
  return HomeAudioItem(
    id: 'track-1',
    lessonId: 'lesson-1',
    lessonTitle: 'Track 1',
    courseId: 'course-1',
    courseTitle: 'Course 1',
    kind: 'audio',
    downloadUrl: downloadUrl,
    signedUrl: signedUrl,
    signedUrlExpiresAt: signedUrlExpiresAt,
  );
}

void main() {
  test('preferredUrl keeps a still-valid signed URL', () {
    final item = _buildItem(
      downloadUrl: '/api/files/audio/fallback.mp3',
      signedUrl: 'https://cdn.test/audio/signed.mp3',
      signedUrlExpiresAt: DateTime.now().toUtc().add(
        const Duration(minutes: 5),
      ),
    );

    expect(item.preferredUrl, 'https://cdn.test/audio/signed.mp3');
  });

  test('preferredUrl falls back when the signed URL is expired', () {
    final item = _buildItem(
      downloadUrl: '/api/files/audio/fallback.mp3',
      signedUrl: 'https://cdn.test/audio/signed.mp3',
      signedUrlExpiresAt: DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      ),
    );

    expect(item.preferredUrl, '/api/files/audio/fallback.mp3');
  });

  test('preferredUrl still exposes the signed URL when no fallback exists', () {
    final item = _buildItem(
      signedUrl: 'https://cdn.test/audio/signed.mp3',
      signedUrlExpiresAt: DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      ),
    );

    expect(item.preferredUrl, 'https://cdn.test/audio/signed.mp3');
  });
}
