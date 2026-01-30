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

    test('replaces /media/stream token URLs with stable /studio/media/{id}', () {
      const id = '123e4567-e89b-12d3-a456-426614174000';
      final token = _jwtForSub(id);
      final markdown = '<img src="/media/stream/$token" />';

      final normalized = normalizeLessonMarkdownForStorage(markdown);

      expect(normalized, contains('/studio/media/$id'));
      expect(normalized, isNot(contains('/media/stream/$token')));
    });
  });
}
