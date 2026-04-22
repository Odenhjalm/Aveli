import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;

import 'package:aveli/editor/adapter/editor_to_markdown.dart'
    as editor_to_markdown;
import 'package:aveli/editor/adapter/markdown_to_editor.dart'
    as markdown_to_editor;
import 'package:aveli/editor/session/editor_operation_controller.dart';
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

String _markdownFromDelta(quill_delta.Delta delta) {
  return editor_to_markdown.editorDeltaToCanonicalMarkdown(delta: delta);
}

quill_delta.Delta _canonicalDocumentDelta(quill_delta.Delta delta) {
  if (delta.toList().isEmpty) {
    return delta;
  }
  final document = quill.Document.fromDelta(delta);
  return document.root.toDelta();
}

void _expectDeltaRoundtrip({
  required quill_delta.Delta delta,
  required String markdown,
}) {
  final serialized = _markdownFromDelta(delta);
  expect(serialized, markdown);

  final reloaded = markdown_to_editor.markdownToEditorDocument(
    markdown: serialized,
  );
  expect(
    _canonicalDocumentDelta(reloaded.toDelta()),
    equals(_canonicalDocumentDelta(delta)),
  );
}

EditorOperationQuillController _buildLoadedController(String markdown) {
  final document = markdown_to_editor.markdownToEditorDocument(
    markdown: markdown,
  );
  return EditorOperationQuillController(
    document: document,
    selection: TextSelection.collapsed(offset: document.length - 1),
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

    test('escaped bold markers normalize into canonical bold on load', () {
      const markdown = r'\*\*Should have been bold\*\*';

      final document = markdown_to_editor.markdownToEditorDocument(
        markdown: markdown,
      );

      expect(document.toPlainText(), 'Should have been bold\n');
      expect(
        _attributesForText(document.toDelta(), 'Should have been bold')['bold'],
        isTrue,
      );
      expect(_roundtripMarkdown(markdown), '**Should have been bold**');
    });

    test('escaped italic markers normalize into canonical italic on load', () {
      const markdown = r'\*Should have been italic\*';

      final document = markdown_to_editor.markdownToEditorDocument(
        markdown: markdown,
      );

      expect(document.toPlainText(), 'Should have been italic\n');
      expect(
        _attributesForText(
          document.toDelta(),
          'Should have been italic',
        )['italic'],
        isTrue,
      );
      expect(_roundtripMarkdown(markdown), '*Should have been italic*');
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

    test('delta italic serializes with a single asterisk marker', () {
      final delta = quill_delta.Delta()
        ..insert('text', {quill.Attribute.italic.key: true})
        ..insert('\n');

      _expectDeltaRoundtrip(delta: delta, markdown: '*text*');
      expect(_markdownFromDelta(delta), isNot('**text**'));
    });

    test('underline html roundtrip survives save and load', () {
      const markdown = '<u>text</u>';

      final document = markdown_to_editor.markdownToEditorDocument(
        markdown: markdown,
      );

      expect(document.toPlainText(), 'text\n');
      expect(
        _attributesForText(document.toDelta(), 'text')['underline'],
        isTrue,
      );

      final saved = _roundtripMarkdown(markdown);
      expect(saved, markdown);

      final reloaded = markdown_to_editor.markdownToEditorDocument(
        markdown: saved,
      );
      expect(
        _attributesForText(reloaded.toDelta(), 'text')['underline'],
        isTrue,
      );
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

    test('mixed italic and bold sentence roundtrips without leakage', () {
      final delta = quill_delta.Delta()
        ..insert('Mix ')
        ..insert('italic', {quill.Attribute.italic.key: true})
        ..insert(' and ')
        ..insert('bold', {quill.Attribute.bold.key: true})
        ..insert('\n');

      _expectDeltaRoundtrip(
        delta: delta,
        markdown: 'Mix *italic* and **bold**',
      );
    });

    test('nested bold and italic markdown roundtrips canonically', () {
      const markdown = '**Bold *Italic***';

      final document = markdown_to_editor.markdownToEditorDocument(
        markdown: markdown,
      );

      expect(document.toPlainText(), 'Bold Italic\n');
      expect(_attributesForText(document.toDelta(), 'Italic')['bold'], isTrue);
      expect(
        _attributesForText(document.toDelta(), 'Italic')['italic'],
        isTrue,
      );
      expect(_roundtripMarkdown(markdown), markdown);
    });

    test('bold and underline roundtrip survives save and load', () {
      const markdown = '**<u>text</u>**';

      final document = markdown_to_editor.markdownToEditorDocument(
        markdown: markdown,
      );
      final attrs = _attributesForText(document.toDelta(), 'text');

      expect(document.toPlainText(), 'text\n');
      expect(attrs['bold'], isTrue);
      expect(attrs['underline'], isTrue);
      expect(_roundtripMarkdown(markdown), markdown);
    });

    test('italic punctuation roundtrips without bold promotion', () {
      final delta = quill_delta.Delta()
        ..insert('really?', {quill.Attribute.italic.key: true})
        ..insert('\n');

      final markdown = _markdownFromDelta(delta);
      expect(markdown, '*really?*');
      expect(markdown, isNot('**really?**'));

      final document = markdown_to_editor.markdownToEditorDocument(
        markdown: markdown,
      );
      expect(document.toPlainText(), 'really?\n');
      expect(
        _attributesForText(document.toDelta(), 'really?')['italic'],
        isTrue,
      );
      expect(document.toPlainText(), isNot(contains('**')));
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
        expect(
          markdown_to_editor.canonicalizeMarkdownForEditor(
            markdown: '<ins>text</ins>',
          ),
          '<u>text</u>',
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
            ),
          ),
        )
        ..insert('\n');

      final markdown = editor_to_markdown.editorDeltaToCanonicalMarkdown(
        delta: delta,
      );

      expect(markdown, '!image(media-image-1)');
    });

    test('underline persists as canonical html before persistence', () {
      final delta = quill_delta.Delta()
        ..insert('underlined', quill.Attribute.underline.toJson())
        ..insert('\n');

      final markdown = editor_to_markdown.editorDeltaToCanonicalMarkdown(
        delta: delta,
      );

      expect(markdown, '<u>underlined</u>');
    });

    test('loaded mixed media document is canonical before first edit', () {
      final document = markdown_to_editor.markdownToEditorDocument(
        markdown: 'Introtext\n\n!image(media-image-1)\n\nEftertext',
      );

      expect(document.toDelta(), equals(document.root.toDelta()));
    });

    test(
      'loaded plain text document accepts first local insert without compose failure',
      () {
        final controller = _buildLoadedController('Introtext\n\nEftertext');

        expect(
          () => controller.replaceText(
            0,
            0,
            'X',
            const TextSelection.collapsed(offset: 1),
          ),
          returnsNormally,
        );
        expect(controller.document.toPlainText(), 'XIntrotext\nEftertext\n');
      },
    );

    test(
      'loaded mixed media document accepts first local insert without compose failure',
      () {
        final controller = _buildLoadedController(
          'Introtext\n\n!image(media-image-1)\n\nEftertext',
        );

        expect(
          () => controller.replaceText(
            0,
            0,
            'X',
            const TextSelection.collapsed(offset: 1),
          ),
          returnsNormally,
        );
        expect(controller.document.toPlainText(), startsWith('XIntrotext'));
      },
    );

    test(
      'loaded formatted media document accepts first local insert without compose failure',
      () {
        final controller = _buildLoadedController(
          '**Introtext**\n\n!audio(media-audio-1)\n\n*Eftertext*',
        );

        expect(
          () => controller.replaceText(
            0,
            0,
            'X',
            const TextSelection.collapsed(offset: 1),
          ),
          returnsNormally,
        );
        expect(controller.document.toPlainText(), startsWith('XIntrotext'));
      },
    );
  });
}
