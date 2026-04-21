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

    test('routes M4A to canonical audio uploads', () {
      expect(
        detectHomePlayerUploadRoute(
          mimeType: 'audio/m4a',
          filename: 'demo.m4a',
        ),
        HomePlayerUploadRoute.directM4a,
      );
      expect(
        detectHomePlayerUploadRoute(
          mimeType: 'audio/mp4',
          filename: 'demo.m4a',
        ),
        HomePlayerUploadRoute.directM4a,
      );
      expect(
        detectHomePlayerUploadRoute(mimeType: '', filename: 'demo.m4a'),
        HomePlayerUploadRoute.directM4a,
      );
      expect(
        homePlayerUploadNormalizedMimeType(HomePlayerUploadRoute.directM4a),
        'audio/m4a',
      );
    });

    test('rejects video because home player is audio-only', () {
      final videoRoute = detectHomePlayerUploadRoute(
        mimeType: 'video/mp4',
        filename: 'demo.mp4',
      );
      expect(videoRoute, HomePlayerUploadRoute.unsupportedVideo);
      expect(
        homePlayerUploadUnsupportedTextId(videoRoute),
        'home.player_upload.unsupported_video_error',
      );
    });

    test('rejects other unsupported types with helpful messages', () {
      final audioRoute = detectHomePlayerUploadRoute(
        mimeType: 'audio/ogg',
        filename: 'demo.ogg',
      );
      expect(audioRoute, HomePlayerUploadRoute.unsupportedAudio);
      expect(
        homePlayerUploadUnsupportedTextId(audioRoute),
        'home.player_upload.unsupported_audio_error',
      );

      final otherRoute = detectHomePlayerUploadRoute(
        mimeType: 'application/pdf',
        filename: 'demo.pdf',
      );
      expect(otherRoute, HomePlayerUploadRoute.unsupportedOther);
      expect(
        homePlayerUploadUnsupportedTextId(otherRoute),
        'home.player_upload.unsupported_other_error',
      );
    });
  });
}
