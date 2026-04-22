import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/editor/guardrails/lesson_markdown_integrity_guard.dart';

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
      expect(result.originalMarkdown, '**Bold** *Italic*\n\n\n\nBody');
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
