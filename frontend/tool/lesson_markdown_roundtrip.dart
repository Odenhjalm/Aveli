import 'dart:convert';
import 'dart:io';

import 'package:aveli/editor/adapter/editor_to_markdown.dart'
    as editor_to_markdown;
import 'package:aveli/editor/adapter/markdown_to_editor.dart'
    as markdown_to_editor;

String roundTripLessonMarkdownPayload(String input) {
  if (input.trim().isEmpty) {
    throw const FormatException(
      'lesson_markdown_roundtrip: missing JSON input',
    );
  }

  final decoded = jsonDecode(input);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
      'lesson_markdown_roundtrip: expected JSON object',
    );
  }

  final rawItems = decoded['items'];
  if (rawItems is! List) {
    throw const FormatException(
      'lesson_markdown_roundtrip: expected "items" list',
    );
  }

  final results = <Map<String, Object?>>[];
  for (final rawItem in rawItems) {
    final item = rawItem is Map ? rawItem : const <Object?, Object?>{};
    final lessonId = '${item['lesson_id'] ?? ''}';
    final markdown = '${item['markdown'] ?? ''}';

    try {
      final document = markdown_to_editor.markdownToEditorDocument(
        markdown: markdown,
      );
      final canonical = editor_to_markdown.editorDeltaToCanonicalMarkdown(
        delta: document.toDelta(),
      );
      results.add(<String, Object?>{
        'lesson_id': lessonId,
        'canonical_markdown': canonical,
        'plain_text': document.toPlainText(),
        'error': null,
      });
    } catch (error, stackTrace) {
      results.add(<String, Object?>{
        'lesson_id': lessonId,
        'canonical_markdown': null,
        'plain_text': null,
        'error': '$error',
        'stack': '$stackTrace',
      });
    }
  }

  return jsonEncode(<String, Object?>{'results': results});
}

Future<void> main() async {
  final input = await stdin.transform(utf8.decoder).join();
  try {
    stdout.writeln(roundTripLessonMarkdownPayload(input));
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  }
}
