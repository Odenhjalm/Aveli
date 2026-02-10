import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/shared/utils/lesson_content_pipeline.dart';

String _jwtForSub(String sub) {
  final header = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'none', 'typ': 'JWT'})))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'sub': sub})))
      .replaceAll('=', '');
  return '$header.$payload.signature';
}

void main() {
  group('Lesson markdown normalization', () {
    test('normalizes absolute /studio/media URLs to relative', () {
      const id = '123e4567-e89b-12d3-a456-426614174000';
      final markdown = '![alt](https://api.example.com/studio/media/$id)';

      final normalized = normalizeLessonMarkdownForStorage(markdown);

      expect(normalized, contains('/studio/media/$id'));
      expect(normalized, isNot(contains('https://api.example.com')));
    });

    test(
      'rewrites /api/files URLs to /studio/media URLs when mapping exists',
      () {
        const id = '123e4567-e89b-12d3-a456-426614174000';
        const apiPath = '/api/files/public-media/course/lesson/file.png';
        const absUrl = 'https://api.example.com$apiPath?download=1';
        final markdown = '<audio controls src="$absUrl"></audio>';

        final rewritten = rewriteLessonMarkdownApiFilesUrls(
          markdown: markdown,
          apiFilesPathToStudioMediaUrl: {apiPath: '/studio/media/$id'},
        );

        expect(rewritten, contains('/studio/media/$id'));
        expect(rewritten, isNot(contains(absUrl)));
      },
    );

    test(
      'replaces /media/stream token URLs with stable /studio/media/{id}',
      () {
        const id = '123e4567-e89b-12d3-a456-426614174000';
        final token = _jwtForSub(id);
        final markdown = '<img src="/media/stream/$token" />';

        final normalized = normalizeLessonMarkdownForStorage(markdown);

        expect(normalized, contains('/studio/media/$id'));
        expect(normalized, isNot(contains('/media/stream/$token')));
      },
    );

    test('legacy video detection: empty and invalid URLs are legacy', () {
      expect(isLegacyVideoEmbed(''), isTrue);
      expect(isLegacyVideoEmbed('ftp://cdn.test/legacy.mp4'), isTrue);
      expect(isLegacyVideoEmbed('/studio/media/legacy-path'), isTrue);
    });

    test('legacy video detection: valid HTTPS embed is not legacy', () {
      expect(isLegacyVideoEmbed('https://cdn.test/video.mp4'), isFalse);
    });

    test(
      'legacy video detection: lesson media marker without playback URL is legacy',
      () {
        const id = '123e4567-e89b-12d3-a456-426614174000';
        final payload = jsonEncode({'lesson_media_id': id, 'kind': 'video'});
        expect(isLegacyVideoEmbed(payload), isTrue);
      },
    );

    test(
      'legacy video detection: structured payload with valid playback URL is not legacy',
      () {
        const id = '123e4567-e89b-12d3-a456-426614174000';
        final payload = jsonEncode({
          'lesson_media_id': id,
          'kind': 'video',
          'src': 'https://cdn.test/video.mp4',
        });
        expect(isLegacyVideoEmbed(payload), isFalse);
      },
    );
  });
}
