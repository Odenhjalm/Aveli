import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;
import 'package:markdown/markdown.dart' as md;

import 'package:aveli/shared/utils/lesson_content_pipeline.dart';

void main() {
  group('Lesson content serialization', () {
    const sampleUrl = 'https://example.com/audio.mp3';
    const sampleImageUrl = 'https://example.com/image.png';
    const sampleVideoUrl = 'https://example.com/video.mp4';
    const sampleLessonMediaId = '123e4567-e89b-12d3-a456-426614174000';

    test('audio embed converts to <audio> HTML on markdown export', () {
      final delta = quill_delta.Delta()
        ..insert('Intro\n')
        ..insert(AudioBlockEmbed.fromUrl(sampleUrl))
        ..insert('\n');

      final markdown = createLessonDeltaToMarkdown().convert(delta);

      expect(markdown, contains('<audio controls src="$sampleUrl"></audio>'));
    });

    test('lesson media audio embed persists as /studio/media marker', () {
      const playbackUrl =
          'https://storage.example.com/audio.mp3?X-Amz-Signature=abc';
      final delta = quill_delta.Delta()
        ..insert('Intro\n')
        ..insert(
          AudioBlockEmbed.fromLessonMedia(
            lessonMediaId: sampleLessonMediaId,
            src: playbackUrl,
          ),
        )
        ..insert('\n');

      final markdown = createLessonDeltaToMarkdown().convert(delta);

      expect(markdown, contains('data-lesson-media-id="$sampleLessonMediaId"'));
      expect(markdown, contains('src="/studio/media/$sampleLessonMediaId"'));
      expect(markdown, isNot(contains(playbackUrl)));
    });

    test('lesson media video embed persists as /studio/media marker', () {
      const playbackUrl =
          'https://storage.example.com/video.mp4?X-Amz-Signature=abc';
      final delta = quill_delta.Delta()
        ..insert('Intro\n')
        ..insert(
          quill.BlockEmbed.video(
            videoBlockEmbedValueFromLessonMedia(
              lessonMediaId: sampleLessonMediaId,
              src: playbackUrl,
            ),
          ),
        )
        ..insert('\n');

      final markdown = createLessonDeltaToMarkdown().convert(delta);

      expect(markdown, contains('data-lesson-media-id="$sampleLessonMediaId"'));
      expect(markdown, contains('src="/studio/media/$sampleLessonMediaId"'));
      expect(markdown, isNot(contains(playbackUrl)));
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

    test('video embed exports without native controls attribute', () {
      final delta = quill_delta.Delta()
        ..insert('Intro\n')
        ..insert(quill.BlockEmbed.video(sampleVideoUrl))
        ..insert('\n');

      final markdown = createLessonDeltaToMarkdown().convert(delta);

      expect(markdown, contains('<video src="$sampleVideoUrl"></video>'));
      expect(markdown, isNot(contains('<video controls')));
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
        final data = switch (value) {
          AudioBlockEmbed() => value.data,
          Map() => value[AudioBlockEmbed.embedType],
          _ => null,
        };
        if (data is String && data.trim().isNotEmpty) {
          if (data.trim() == sampleUrl) return true;
          if (data.trim().startsWith('{') && data.trim().endsWith('}')) {
            try {
              final decoded = jsonDecode(data) as Map;
              return decoded['src'] == sampleUrl;
            } catch (_) {}
          }
        }
        return false;
      });

      expect(hasAudioEmbed, isTrue);
    });

    test(
      'structured lesson media audio HTML converts back to custom embed',
      () {
        final document = md.Document(
          encodeHtml: false,
          extensionSet: md.ExtensionSet.gitHubWeb,
        );
        const playbackUrl =
            'https://storage.example.com/audio.mp3?X-Amz-Signature=abc';
        const markdown =
            '''
Intro

<audio controls data-lesson-media-id="$sampleLessonMediaId" src="$playbackUrl"></audio>
''';

        final converter = createLessonMarkdownToDelta(document);
        final delta = convertLessonMarkdownToDelta(converter, markdown);

        final hasStructured = delta.toList().any((operation) {
          if (!operation.isInsert) return false;
          final value = operation.value;
          final data = switch (value) {
            AudioBlockEmbed() => value.data,
            Map() => value[AudioBlockEmbed.embedType],
            _ => null,
          };
          if (data is! String) return false;
          if (!data.trim().startsWith('{')) return false;
          try {
            final decoded = jsonDecode(data) as Map;
            return decoded['lesson_media_id'] == sampleLessonMediaId &&
                decoded['src'] == playbackUrl;
          } catch (_) {
            return false;
          }
        });

        expect(hasStructured, isTrue);
      },
    );

    test(
      'structured lesson media video HTML converts back to video embed payload',
      () {
        final document = md.Document(
          encodeHtml: false,
          extensionSet: md.ExtensionSet.gitHubWeb,
        );
        const playbackUrl =
            'https://storage.example.com/video.mp4?X-Amz-Signature=abc';
        const markdown =
            '''
Intro

<video controls data-lesson-media-id="$sampleLessonMediaId" src="$playbackUrl"></video>
''';

        final converter = createLessonMarkdownToDelta(document);
        final delta = convertLessonMarkdownToDelta(converter, markdown);

        final hasStructured = delta.toList().any((operation) {
          if (!operation.isInsert) return false;
          final value = operation.value;
          final data = switch (value) {
            quill.Embeddable() when value.type == quill.BlockEmbed.videoType =>
              value.data,
            Map() => value[quill.BlockEmbed.videoType],
            _ => null,
          };
          if (data is! String) return false;
          if (!data.trim().startsWith('{')) return false;
          try {
            final decoded = jsonDecode(data) as Map;
            return decoded['lesson_media_id'] == sampleLessonMediaId &&
                decoded['src'] == playbackUrl;
          } catch (_) {
            return false;
          }
        });

        expect(hasStructured, isTrue);
      },
    );

    test(
      'img HTML converts back to image embed with style on markdown import',
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
            if (value[quill.BlockEmbed.imageType] != sampleImageUrl)
              return false;
          } else {
            return false;
          }
          final attrs = operation.attributes;
          if (attrs == null) return false;
          return attrs[quill.Attribute.style.key] == style;
        });

        expect(hasStyledImage, isTrue);
      },
    );

    test('img HTML does not survive as raw text on markdown import', () {
      final document = md.Document(
        encodeHtml: false,
        extensionSet: md.ExtensionSet.gitHubWeb,
      );
      const markdown =
          '<img src="$sampleImageUrl" style="width: 111; height: 222;" />\n';

      final converter = createLessonMarkdownToDelta(document);
      final delta = convertLessonMarkdownToDelta(converter, markdown);

      final hasRawHtml = delta.toList().any((operation) {
        if (!operation.isInsert) return false;
        final value = operation.value;
        return value is String && value.contains('<img');
      });

      expect(hasRawHtml, isFalse);
    });

    test('empty audio/video embed src values do not crash markdown import', () {
      final document = md.Document(
        encodeHtml: false,
        extensionSet: md.ExtensionSet.gitHubWeb,
      );
      const markdown = '''
<audio controls src=""></audio>
<video controls src=""></video>
<audio controls></audio>
<video controls></video>
''';

      final converter = createLessonMarkdownToDelta(document);
      late final quill_delta.Delta delta;
      expect(() {
        delta = convertLessonMarkdownToDelta(converter, markdown);
      }, returnsNormally);

      final rawText = delta
          .toList()
          .where((operation) => operation.isInsert && operation.value is String)
          .map((operation) => operation.value as String)
          .join('\n');

      expect(rawText, contains('<audio'));
      expect(rawText, contains('<video'));
    });
  });
}
