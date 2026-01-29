import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;
import 'package:markdown/markdown.dart' as md;

import 'package:aveli/features/studio/presentation/course_editor_page.dart';

void main() {
  group('Lesson content serialization', () {
    const sampleUrl = 'https://example.com/audio.mp3';
    const sampleImageUrl = 'https://example.com/image.png';

    test('audio embed converts to <audio> HTML on markdown export', () {
      final delta = quill_delta.Delta()
        ..insert('Intro\n')
        ..insert(AudioBlockEmbed.fromUrl(sampleUrl))
        ..insert('\n');

      final markdown = createLessonDeltaToMarkdown().convert(delta);

      expect(markdown, contains('<audio controls src="$sampleUrl"></audio>'));
    });

    test('resized image embed converts to <img> HTML on markdown export', () {
      const style = 'width: 200; height: 100;';
      final delta = quill_delta.Delta()
        ..insert('Intro\n')
        ..insert(quill.BlockEmbed.image(sampleImageUrl), {
          quill.Attribute.style.key: style,
        })
        ..insert('\n');

      final markdown = createLessonDeltaToMarkdown().convert(delta);

      expect(markdown, contains('<img'));
      expect(markdown, contains('src="$sampleImageUrl"'));
      expect(markdown, contains('style="$style"'));
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

    test('img HTML converts back to image embed with style on markdown import',
        () {
      final document = md.Document(
        encodeHtml: false,
        extensionSet: md.ExtensionSet.gitHubWeb,
      );
      const style = 'width: 222; height: 111;';
      const markdown = '<img src="$sampleImageUrl" style="$style" />\n';

      final converter = createLessonMarkdownToDelta(document);
      final delta = convertLessonMarkdownToDelta(converter, markdown);

      final hasStyledImage = delta.toList().any((operation) {
        if (!operation.isInsert) return false;
        final value = operation.value;
        if (value is quill.Embeddable) {
          if (value.type != quill.BlockEmbed.imageType) return false;
          if (value.data != sampleImageUrl) return false;
        } else if (value is Map) {
          if (value[quill.BlockEmbed.imageType] != sampleImageUrl) return false;
        } else {
          return false;
        }
        final attrs = operation.attributes;
        if (attrs == null) return false;
        return attrs[quill.Attribute.style.key] == style;
      });

      expect(hasStyledImage, isTrue);
    });
  });
}
