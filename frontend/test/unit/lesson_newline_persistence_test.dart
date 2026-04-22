import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/quill_delta.dart' as quill_delta;

import 'package:aveli/editor/adapter/editor_to_markdown.dart'
    as editor_to_markdown;
import 'package:aveli/editor/adapter/markdown_to_editor.dart'
    as markdown_to_editor;

String _visible(String value) {
  return value
      .replaceAll('\\', r'\\')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n')
      .replaceAll('\t', r'\t');
}

void main() {
  group('Lesson newline persistence', () {
    test('two-paragraph fixture saves as canonical markdown and reloads stably', () {
      const editedPlainText = 'Hello world\n\nThis is a lesson\n';
      const canonicalMarkdown = 'Hello world\n\nThis is a lesson';

      final deltaEdited = quill_delta.Delta()..insert(editedPlainText);
      final editedMarkdown =
          editor_to_markdown.editorDeltaToCanonicalMarkdown(delta: deltaEdited);

      expect(editedMarkdown, canonicalMarkdown);
      expect(editedMarkdown, isNot(contains('\u200B')));

      printOnFailure(
        '[LessonTraceTest] editedMarkdown="${_visible(editedMarkdown)}" (length=${editedMarkdown.length})',
      );

      final reloadedDoc = markdown_to_editor.markdownToEditorDocument(
        markdown: editedMarkdown,
      );
      final reloadedPlainText = reloadedDoc.toPlainText();
      final resavedMarkdown = editor_to_markdown.editorDeltaToCanonicalMarkdown(
        delta: reloadedDoc.toDelta(),
      );

      printOnFailure(
        '[LessonTraceTest] reloadedPlainText="${_visible(reloadedPlainText)}" (length=${reloadedPlainText.length})',
      );

      expect(reloadedPlainText, isNot(contains('\u200B')));
      expect(
        resavedMarkdown,
        canonicalMarkdown,
        reason: 'The locked two-paragraph fixture must remain stable after reload.',
      );
    });
  });
}
