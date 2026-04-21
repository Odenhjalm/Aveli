import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/studio/widgets/home_player_upload_routing.dart';

void main() {
  group('detectHomePlayerUploadRoute', () {
    test('routes WAV to the media pipeline', () {
      expect(
        detectHomePlayerUploadRoute(
          mimeType: 'audio/wav',
          filename: 'demo.wav',
        ),
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

    test('routes MP3 to canonical audio uploads', () {
      expect(
        detectHomePlayerUploadRoute(
          mimeType: 'audio/mpeg',
          filename: 'demo.mp3',
        ),
        HomePlayerUploadRoute.directMp3,
      );
      expect(
        detectHomePlayerUploadRoute(
          mimeType: 'audio/mp3',
          filename: 'demo.mp3',
        ),
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

    test('rejects video because home player is audio-only', () {
      final videoRoute = detectHomePlayerUploadRoute(
        mimeType: 'video/mp4',
        filename: 'demo.mp4',
      );
      expect(videoRoute, HomePlayerUploadRoute.unsupportedVideo);
      expect(
        homePlayerUploadUnsupportedMessage(videoRoute),
        contains('bara ljud'),
      );
    });

    test('rejects other unsupported types with helpful messages', () {
      final audioRoute = detectHomePlayerUploadRoute(
        mimeType: 'audio/ogg',
        filename: 'demo.ogg',
      );
      expect(audioRoute, HomePlayerUploadRoute.unsupportedAudio);
      expect(
        homePlayerUploadUnsupportedMessage(audioRoute),
        contains('WAV eller MP3'),
      );

      final otherRoute = detectHomePlayerUploadRoute(
        mimeType: 'application/pdf',
        filename: 'demo.pdf',
      );
      expect(otherRoute, HomePlayerUploadRoute.unsupportedOther);
      expect(
        homePlayerUploadUnsupportedMessage(otherRoute),
        contains('WAV- eller MP3'),
      );
    });
  });
}
