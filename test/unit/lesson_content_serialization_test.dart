import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/quill_delta.dart' as quill_delta;
import 'package:markdown/markdown.dart' as md;

import 'package:wisdom/features/studio/presentation/course_editor_page.dart';

void main() {
  group('Lesson content serialization', () {
    const sampleUrl = 'https://example.com/audio.mp3';

    test('audio embed converts to <audio> HTML on markdown export', () {
      final delta = quill_delta.Delta()
        ..insert('Intro\n')
        ..insert(AudioBlockEmbed.fromUrl(sampleUrl))
        ..insert('\n');

      final markdown = createLessonDeltaToMarkdown().convert(delta);

      expect(markdown, contains('<audio controls src="$sampleUrl"></audio>'));
    });

    test('audio HTML converts back to custom embed on markdown import', () {
      final document = md.Document(
        encodeHtml: false,
        extensionSet: md.ExtensionSet.gitHubWeb,
      );
      const markdown =
          '''
Intro

<audio controls src="$sampleUrl"></audio>
''';

      final converter = createLessonMarkdownToDelta(document);
      final delta = convertLessonMarkdownToDelta(converter, markdown);

      final hasAudioEmbed = delta.toList().any((operation) {
        if (!operation.isInsert) return false;
        final value = operation.value;
        if (value is AudioBlockEmbed) {
          return value.data == sampleUrl;
        }
        if (value is Map) {
          final dynamic url = value[AudioBlockEmbed.embedType];
          return url == sampleUrl;
        }
        return false;
      });

      expect(hasAudioEmbed, isTrue);
    });
  });
}
