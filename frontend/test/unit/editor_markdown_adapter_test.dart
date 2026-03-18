import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;

import 'package:aveli/editor/adapter/editor_to_markdown.dart'
    as editor_to_markdown;
import 'package:aveli/editor/adapter/markdown_to_editor.dart'
    as markdown_to_editor;
import 'package:aveli/shared/utils/lesson_content_pipeline.dart'
    as lesson_pipeline;

Map<String, dynamic> _attributesForText(quill_delta.Delta delta, String text) {
  for (final operation in delta.toList()) {
    if (!operation.isInsert || operation.value != text) {
      continue;
    }
    return Map<String, dynamic>.from(operation.attributes ?? const {});
  }
  return const <String, dynamic>{};
}

Map<String, dynamic> _attributesForNewline(quill_delta.Delta delta) {
  for (final operation in delta.toList()) {
    if (!operation.isInsert || operation.value != '\n') {
      continue;
    }
    return Map<String, dynamic>.from(operation.attributes ?? const {});
  }
  return const <String, dynamic>{};
}

String _roundtripMarkdown(String markdown) {
  final document = markdown_to_editor.markdownToEditorDocument(
    markdown: markdown,
  );
  return editor_to_markdown.editorDeltaToCanonicalMarkdown(
    delta: document.toDelta(),
  );
}

void main() {
  group('Editor Markdown adapters', () {
    test('bold roundtrip survives save and load', () {
      const markdown = '**text**';

      final document = markdown_to_editor.markdownToEditorDocument(
        markdown: markdown,
      );

      expect(document.toPlainText(), 'text\n');
      expect(_attributesForText(document.toDelta(), 'text')['bold'], isTrue);

      final saved = _roundtripMarkdown(markdown);
      expect(saved, markdown);

      final reloaded = markdown_to_editor.markdownToEditorDocument(
        markdown: saved,
      );
      expect(_attributesForText(reloaded.toDelta(), 'text')['bold'], isTrue);
    });

    test('italic roundtrip survives save and load', () {
      const markdown = '*text*';

      final document = markdown_to_editor.markdownToEditorDocument(
        markdown: markdown,
      );

      expect(document.toPlainText(), 'text\n');
      expect(_attributesForText(document.toDelta(), 'text')['italic'], isTrue);
      expect(_roundtripMarkdown(markdown), markdown);
    });

    test('bold and italic roundtrip survives save and load', () {
      const markdown = '***text***';

      final document = markdown_to_editor.markdownToEditorDocument(
        markdown: markdown,
      );
      final attrs = _attributesForText(document.toDelta(), 'text');

      expect(document.toPlainText(), 'text\n');
      expect(attrs['bold'], isTrue);
      expect(attrs['italic'], isTrue);
      expect(_roundtripMarkdown(markdown), markdown);
    });

    test('heading roundtrip survives save and load', () {
      const markdown = '## heading';

      final document = markdown_to_editor.markdownToEditorDocument(
        markdown: markdown,
      );

      expect(document.toPlainText(), 'heading\n');
      expect(_attributesForNewline(document.toDelta())['header'], 2);
      expect(_roundtripMarkdown(markdown), markdown);
    });

    test('bullet list roundtrip remains stable', () {
      const markdown = '- first\n- second';
      expect(_roundtripMarkdown(markdown), markdown);
    });

    test('media token roundtrip survives save and load', () {
      const markdown = '!image(media-image-1)';

      final document = markdown_to_editor.markdownToEditorDocument(
        markdown: markdown,
      );
      final lessonMediaIds = document
          .toDelta()
          .toList()
          .map((operation) => operation.value)
          .map(
            (value) => switch (value) {
              quill.Embeddable() => lesson_pipeline.lessonMediaIdFromEmbedValue(
                value.data,
              ),
              Map() => lesson_pipeline.lessonMediaIdFromEmbedValue(
                value[quill.BlockEmbed.imageType],
              ),
              _ => null,
            },
          )
          .whereType<String>()
          .toList();

      expect(lessonMediaIds, contains('media-image-1'));
      expect(_roundtripMarkdown(markdown), markdown);
    });

    test(
      'supported bold markdown never appears as literal markers in editor',
      () {
        const markdown = '**text**';

        final document = markdown_to_editor.markdownToEditorDocument(
          markdown: markdown,
        );

        expect(document.toPlainText(), isNot(contains('**')));
        expect(document.toPlainText(), 'text\n');
      },
    );

    test(
      'adapter canonicalizes legacy emphasis markers to contract format',
      () {
        expect(
          markdown_to_editor.canonicalizeMarkdownForEditor(markdown: '_text_'),
          '*text*',
        );
        expect(
          markdown_to_editor.canonicalizeMarkdownForEditor(
            markdown: '__text__',
          ),
          '**text**',
        );
        expect(
          markdown_to_editor.canonicalizeMarkdownForEditor(
            markdown: '**_text_**',
          ),
          '***text***',
        );
        expect(_roundtripMarkdown('* text *'), '*text*');
        expect(_roundtripMarkdown('** text **'), '**text**');
        expect(_roundtripMarkdown('*** text ***'), '***text***');
      },
    );

    test('image embeds with lesson media ids persist as canonical tokens', () {
      final delta = quill_delta.Delta()
        ..insert(
          quill.BlockEmbed.image(
            lesson_pipeline.imageBlockEmbedValueFromLessonMedia(
              lessonMediaId: 'media-image-1',
              src: 'https://cdn.test/media-image-1.webp',
            ),
          ),
        )
        ..insert('\n');

      final markdown = editor_to_markdown.editorDeltaToCanonicalMarkdown(
        delta: delta,
      );

      expect(markdown, '!image(media-image-1)');
    });

    test('underline is stripped before persistence', () {
      final delta = quill_delta.Delta()
        ..insert('underlined', quill.Attribute.underline.toJson())
        ..insert('\n');

      final markdown = editor_to_markdown.editorDeltaToCanonicalMarkdown(
        delta: delta,
      );

      expect(markdown, 'underlined');
    });
  });
}
