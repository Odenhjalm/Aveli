import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;
import 'package:markdown/markdown.dart' as md;

import 'package:aveli/shared/utils/lesson_content_pipeline.dart';

String _visible(String value) {
  return value
      .replaceAll('\\', r'\\')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n')
      .replaceAll('\t', r'\t');
}

void main() {
  group('Lesson newline persistence', () {
    test('paragraph/newline survives markdown save + reload', () {
      const initialPlainText = 'Hello world\nThis is a lesson\n';
      const editedPlainText = 'Hello world\n\nThis is a lesson\n';

      final deltaInitial = quill_delta.Delta()..insert(initialPlainText);
      final deltaEdited = quill_delta.Delta()..insert(editedPlainText);

      final exporter = createLessonDeltaToMarkdown();
      final initialMarkdown = exporter.convert(deltaInitial);
      final editedMarkdown = exporter.convert(deltaEdited);

      expect(editedMarkdown, isNot(contains('\u200B')));

      // Trace output with visible markers for newline debugging.
      printOnFailure(
        '[LessonTraceTest] initialMarkdown="${_visible(initialMarkdown)}" (length=${initialMarkdown.length})',
      );
      printOnFailure(
        '[LessonTraceTest] editedMarkdown="${_visible(editedMarkdown)}" (length=${editedMarkdown.length})',
      );

      final document = md.Document(
        encodeHtml: false,
        extensionSet: md.ExtensionSet.gitHubWeb,
      );
      final importer = createLessonMarkdownToDelta(document);
      final deltaReloaded = convertLessonMarkdownToDelta(importer, editedMarkdown);
      final reloadedDoc = quill.Document.fromDelta(deltaReloaded);
      final reloadedPlainText = reloadedDoc.toPlainText();

      printOnFailure(
        '[LessonTraceTest] reloadedPlainText="${_visible(reloadedPlainText)}" (length=${reloadedPlainText.length})',
      );

      expect(reloadedPlainText, isNot(contains('\u200B')));
      expect(
        reloadedPlainText,
        editedPlainText,
        reason:
            'Newline-only edits must persist after markdown round-trip (save + reload).',
      );
    });
  });
}
