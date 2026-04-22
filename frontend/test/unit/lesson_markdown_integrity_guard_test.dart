import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/editor/adapter/markdown_to_editor.dart'
    as markdown_to_editor;
import 'package:aveli/editor/guardrails/lesson_markdown_integrity_guard.dart';
import 'package:aveli/editor/normalization/quill_delta_normalizer.dart';

quill_delta.Delta _plainTextDelta(String text) {
  return quill_delta.Delta()
    ..insert(text)
    ..insert('\n');
}

void main() {
  group('Lesson markdown integrity guard', () {
    test('valid italic passes', () {
      final result = validateLessonMarkdownIntegrity(
        delta: quill_delta.Delta()
          ..insert('Italic', {quill.Attribute.italic.key: true})
          ..insert('\n'),
      );

      expect(result.ok, isTrue);
      expect(result.failureReason, isNull);
      expect(result.originalMarkdown, '*Italic*');
      expect(result.canonicalMarkdown, '*Italic*');
    });

    test('valid bold passes', () {
      final result = validateLessonMarkdownIntegrity(
        delta: quill_delta.Delta()
          ..insert('Bold', {quill.Attribute.bold.key: true})
          ..insert('\n'),
      );

      expect(result.ok, isTrue);
      expect(result.originalMarkdown, '**Bold**');
      expect(result.canonicalMarkdown, '**Bold**');
    });

    test('valid mixed emphasis passes', () {
      final result = validateLessonMarkdownIntegrity(
        delta: quill_delta.Delta()
          ..insert('Mix ')
          ..insert('Italic', {quill.Attribute.italic.key: true})
          ..insert(' and ')
          ..insert('Bold', {quill.Attribute.bold.key: true})
          ..insert('\n'),
      );

      expect(result.ok, isTrue);
      expect(result.originalMarkdown, 'Mix *Italic* and **Bold**');
      expect(result.canonicalMarkdown, 'Mix *Italic* and **Bold**');
    });

    test('valid nested emphasis passes when supported canonically', () {
      final result = validateLessonMarkdownIntegrity(
        delta: quill_delta.Delta()
          ..insert('Bold ', {quill.Attribute.bold.key: true})
          ..insert('Italic', {
            quill.Attribute.bold.key: true,
            quill.Attribute.italic.key: true,
          })
          ..insert('\n'),
      );

      expect(result.ok, isTrue);
      expect(result.originalMarkdown, '**Bold *Italic***');
      expect(result.canonicalMarkdown, '**Bold *Italic***');
    });

    test('valid formatted content with redundant blank lines passes', () {
      final result = validateLessonMarkdownIntegrity(
        delta: quill_delta.Delta()
          ..insert('Bold', {quill.Attribute.bold.key: true})
          ..insert(' ')
          ..insert('Italic', {quill.Attribute.italic.key: true})
          ..insert('\n')
          ..insert('\n')
          ..insert('Body')
          ..insert('\n'),
      );

      expect(result.ok, isTrue);
      expect(result.originalMarkdown, '**Bold** *Italic*\n\nBody');
      expect(result.canonicalMarkdown, '**Bold** *Italic*\n\nBody');
    });

    test('valid block spacing normalization passes', () {
      final result = validateLessonMarkdownIntegrity(
        delta: quill_delta.Delta()
          ..insert('Heading')
          ..insert('\n', {quill.Attribute.header.key: 2})
          ..insert('\n')
          ..insert('Body')
          ..insert('\n'),
      );

      expect(result.ok, isTrue);
      expect(result.originalMarkdown, '## Heading\n\n\nBody');
      expect(result.canonicalMarkdown, '## Heading\nBody');
    });

    test('canonical two-paragraph fixture passes', () {
      const markdown = 'Hello world\n\nThis is a lesson';
      final result = validateLessonMarkdownIntegrity(
        delta: markdown_to_editor
            .markdownToEditorDocument(markdown: markdown)
            .toDelta(),
      );

      expect(result.ok, isTrue);
      expect(result.failureReason, isNull);
      expect(result.originalMarkdown, markdown);
      expect(result.canonicalMarkdown, markdown);
    });

    test('canonical inline document fixture passes with studio label map', () {
      const markdown = 'Intro\n\n!document(media-document-1)\n\nOutro';
      const lessonMediaDocumentLabelsById = <String, String>{
        'media-document-1': 'guide.pdf',
      };
      final hydration = markdown_to_editor.hydrateLessonMarkdownForEditor(
        markdown: markdown,
        lessonMediaDocumentLabelsById: lessonMediaDocumentLabelsById,
      );
      final result = validateLessonMarkdownIntegrity(
        delta: hydration.document.toDelta(),
        lessonMediaDocumentLabelsById: lessonMediaDocumentLabelsById,
      );

      expect(result.ok, isTrue);
      expect(result.failureReason, isNull);
      expect(result.originalMarkdown, markdown);
      expect(result.canonicalMarkdown, markdown);
    });

    test('canonical heading3 with bold and italic at document end passes', () {
      const markdown = '### Heading3\n**Bold**\n*Italic*';
      const canonicalMarkdown = '### Heading3\n**Bold** *Italic*';
      final result = validateLessonMarkdownIntegrity(
        delta: markdown_to_editor
            .markdownToEditorDocument(markdown: markdown)
            .toDelta(),
      );

      expect(result.ok, isTrue);
      expect(result.failureReason, isNull);
      expect(result.originalMarkdown, canonicalMarkdown);
      expect(result.canonicalMarkdown, canonicalMarkdown);
    });

    test(
      'normalizer canonicalizes italic last line into a clean newline op',
      () {
        const markdown = '*Italic last line*';
        final normalized = normalizeDeltaForGuard(
          quill_delta.Delta()
            ..insert('Italic last line\n', {quill.Attribute.italic.key: true}),
        );
        final result = validateLessonMarkdownIntegrity(delta: normalized);

        expect(normalized.toJson(), <Object?>[
          <String, Object?>{
            'insert': 'Italic last line',
            'attributes': <String, Object?>{'italic': true},
          },
          <String, Object?>{'insert': '\n'},
        ]);
        expect(result.ok, isTrue);
        expect(result.failureReason, isNull);
        expect(result.originalMarkdown, markdown);
        expect(result.canonicalMarkdown, markdown);
      },
    );

    test(
      'normalizer stabilizes split end-of-document heading3 bold italic delta',
      () {
        final normalized = normalizeDeltaForGuard(
          quill_delta.Delta()
            ..insert('Heading3')
            ..insert('\n', {quill.Attribute.header.key: 3})
            ..insert('Bo', {quill.Attribute.bold.key: true})
            ..insert('ld', {quill.Attribute.bold.key: true})
            ..insert('', {quill.Attribute.bold.key: true})
            ..insert(' ')
            ..insert('It', {quill.Attribute.italic.key: true})
            ..insert('alic', {quill.Attribute.italic.key: true})
            ..insert('\n', {quill.Attribute.italic.key: true})
            ..insert('', {quill.Attribute.italic.key: true}),
        );
        final result = validateLessonMarkdownIntegrity(delta: normalized);

        expect(normalized.toJson(), <Object?>[
          <String, Object?>{'insert': 'Heading3'},
          <String, Object?>{
            'insert': '\n',
            'attributes': <String, Object?>{'header': 3},
          },
          <String, Object?>{
            'insert': 'Bold',
            'attributes': <String, Object?>{'bold': true},
          },
          <String, Object?>{'insert': ' '},
          <String, Object?>{
            'insert': 'Italic',
            'attributes': <String, Object?>{'italic': true},
          },
          <String, Object?>{'insert': '\n'},
        ]);
        expect(result.ok, isTrue);
        expect(result.failureReason, isNull);
        expect(result.originalMarkdown, '### Heading3\n**Bold** *Italic*');
        expect(result.canonicalMarkdown, '### Heading3\n**Bold** *Italic*');
      },
    );

    test('malformed spaced emphasis fails closed', () {
      final result = validateLessonMarkdownIntegrity(
        delta: _plainTextDelta('before ** spaced ** after'),
      );

      expect(result.ok, isFalse);
      expect(
        result.failureReason,
        LessonMarkdownIntegrityFailureReason.semanticRoundTripMismatch,
      );
    });

    test('escaped emphasis leakage fails closed', () {
      final result = validateLessonMarkdownIntegrity(
        delta: _plainTextDelta('*italic*'),
      );

      expect(result.ok, isFalse);
      expect(
        result.failureReason,
        LessonMarkdownIntegrityFailureReason.semanticRoundTripMismatch,
      );
      expect(result.originalMarkdown, '*italic*');
      expect(result.canonicalMarkdown, '*italic*');
    });

    test('malformed mixed wrappers fail closed', () {
      final result = validateLessonMarkdownIntegrity(
        delta: _plainTextDelta('**_text_**'),
      );

      expect(result.ok, isFalse);
      expect(result.failureReason, isNotNull);
    });
  });
}
