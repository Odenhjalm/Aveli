import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/lesson_markdown_roundtrip.dart' as roundtrip_tool;

void main() {
  group('Lesson markdown roundtrip tool', () {
    test(
      'returns shared comparison fields for locked newline and document fixtures',
      () {
        final payload = jsonEncode(<String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'lesson_id': 'lesson-newline',
              'markdown': 'Hello world\n\nThis is a lesson',
            },
            <String, Object?>{
              'lesson_id': 'lesson-document',
              'markdown': 'Intro\n\n!document(media-document-1)\n\nOutro',
            },
          ],
        });

        final decoded =
            jsonDecode(roundtrip_tool.roundTripLessonMarkdownPayload(payload))
                as Map<String, dynamic>;
        final results = decoded['results'] as List<dynamic>;
        final newline = results[0] as Map<String, dynamic>;
        final document = results[1] as Map<String, dynamic>;

        expect(
          newline['input_comparison_markdown'],
          'Hello world\n\nThis is a lesson',
        );
        expect(
          newline['canonical_comparison_markdown'],
          'Hello world\n\nThis is a lesson',
        );
        expect(
          document['canonical_markdown'],
          'Intro\n\n!document(media-document-1)\n\nOutro',
        );
        expect(
          document['canonical_comparison_markdown'],
          'Intro\n\n!document(media-document-1)\n\nOutro',
        );
        expect(document['plain_text'], contains('Ladda ner dokument'));
      },
    );

    test('preserves mismatch signal for malformed escaped emphasis input', () {
      final payload = jsonEncode(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'lesson_id': 'lesson-malformed',
            'markdown': r'This is plain, \*italic\*, and **bold**.',
          },
        ],
      });

      final decoded =
          jsonDecode(roundtrip_tool.roundTripLessonMarkdownPayload(payload))
              as Map<String, dynamic>;
      final result =
          (decoded['results'] as List<dynamic>).single as Map<String, dynamic>;

      expect(
        result['input_comparison_markdown'],
        r'This is plain, \*italic\*, and **bold**.',
      );
      expect(
        result['canonical_comparison_markdown'],
        'This is plain, *italic*, and **bold**.',
      );
    });
  });
}
