import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/studio/widgets/home_player_upload_routing.dart';

void main() {
  group('detectHomePlayerUploadRoute', () {
    test('routes WAV to the media pipeline', () {
      expect(
        detectHomePlayerUploadRoute(mimeType: 'audio/wav', filename: 'demo.wav'),
        HomePlayerUploadRoute.wavPipeline,
      );
      expect(
        detectHomePlayerUploadRoute(
          mimeType: 'audio/vnd.wave',
          filename: 'demo.WAV',
        ),
        HomePlayerUploadRoute.wavPipeline,
      );
      expect(
        detectHomePlayerUploadRoute(mimeType: '', filename: 'demo.wav'),
        HomePlayerUploadRoute.wavPipeline,
      );
    });

    test('routes MP3 to direct uploads', () {
      expect(
        detectHomePlayerUploadRoute(
          mimeType: 'audio/mpeg',
          filename: 'demo.mp3',
        ),
        HomePlayerUploadRoute.directMp3,
      );
      expect(
        detectHomePlayerUploadRoute(mimeType: 'audio/mp3', filename: 'demo.mp3'),
        HomePlayerUploadRoute.directMp3,
      );
      expect(
        detectHomePlayerUploadRoute(mimeType: '', filename: 'demo.mp3'),
        HomePlayerUploadRoute.directMp3,
      );
      expect(
        homePlayerUploadNormalizedMimeType(HomePlayerUploadRoute.directMp3),
        'audio/mpeg',
      );
    });

    test('routes MP4 to direct uploads', () {
      expect(
        detectHomePlayerUploadRoute(mimeType: 'video/mp4', filename: 'demo.mp4'),
        HomePlayerUploadRoute.directMp4,
      );
      expect(
        detectHomePlayerUploadRoute(mimeType: '', filename: 'demo.mp4'),
        HomePlayerUploadRoute.directMp4,
      );
      expect(
        homePlayerUploadNormalizedMimeType(HomePlayerUploadRoute.directMp4),
        'video/mp4',
      );
    });

    test('rejects unsupported types with helpful messages', () {
      final audioRoute = detectHomePlayerUploadRoute(
        mimeType: 'audio/ogg',
        filename: 'demo.ogg',
      );
      expect(audioRoute, HomePlayerUploadRoute.unsupportedAudio);
      expect(
        homePlayerUploadUnsupportedMessage(audioRoute),
        contains('WAV eller MP3'),
      );

      final videoRoute = detectHomePlayerUploadRoute(
        mimeType: 'video/quicktime',
        filename: 'demo.mov',
      );
      expect(videoRoute, HomePlayerUploadRoute.unsupportedVideo);
      expect(
        homePlayerUploadUnsupportedMessage(videoRoute),
        contains('MP4'),
      );

      final otherRoute = detectHomePlayerUploadRoute(
        mimeType: 'application/pdf',
        filename: 'demo.pdf',
      );
      expect(otherRoute, HomePlayerUploadRoute.unsupportedOther);
      expect(
        homePlayerUploadUnsupportedMessage(otherRoute),
        contains('WAV-, MP3- eller MP4'),
      );
    });
  });
}

