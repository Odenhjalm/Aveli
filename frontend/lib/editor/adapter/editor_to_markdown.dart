import 'package:flutter_quill/quill_delta.dart' as quill_delta;

import 'package:aveli/editor/adapter/markdown_to_editor.dart'
    show canonicalizeSupportedMarkdown;
import 'package:aveli/shared/utils/lesson_content_pipeline.dart'
    as lesson_pipeline;

const Set<String> _allowedInlineAttributeKeys = <String>{
  'bold',
  'italic',
  'link',
};

String _stripTerminalDocumentNewline(String markdown) {
  return markdown.replaceFirst(RegExp(r'\n+$'), '');
}

String rewriteMarkdownUrls({
  required String markdown,
  required Map<String, String> urlToReplacement,
}) {
  if (markdown.isEmpty || urlToReplacement.isEmpty) return markdown;

  final entries = urlToReplacement.entries.toList(growable: false)
    ..sort((left, right) => right.key.length.compareTo(left.key.length));

  var rewritten = markdown;
  for (final entry in entries) {
    rewritten = rewritten.replaceAll(entry.key, entry.value);
  }
  return rewritten;
}

Map<String, dynamic>? _sanitizeAttributes(
  Map<String, dynamic>? attributes, {
  required bool isLineBreak,
}) {
  if (attributes == null || attributes.isEmpty) return null;

  final sanitized = <String, dynamic>{};
  for (final entry in attributes.entries) {
    if (_allowedInlineAttributeKeys.contains(entry.key) &&
        entry.value != null &&
        entry.value != false) {
      sanitized[entry.key] = entry.value;
    }
  }

  if (isLineBreak) {
    final header = attributes['header'];
    if (header is num) {
      final level = header.toInt();
      if (level >= 1 && level <= 3) {
        sanitized['header'] = level;
      }
    }

    final list = attributes['list'];
    if (list is String) {
      if (list == 'ordered' || list == 'bullet') {
        sanitized['list'] = list;
      } else if (list == 'checked' || list == 'unchecked') {
        sanitized['list'] = 'bullet';
      }
    }

    final indent = attributes['indent'];
    if (indent is num && indent.toInt() > 0) {
      sanitized['indent'] = indent.toInt();
    }
  }

  return sanitized.isEmpty ? null : sanitized;
}

quill_delta.Delta sanitizeEditorDeltaForCanonicalMarkdown(
  quill_delta.Delta source,
) {
  final result = quill_delta.Delta();

  for (final operation in source.toList()) {
    if (!operation.isInsert) {
      result.push(operation);
      continue;
    }

    final value = operation.value;
    final sanitized = _sanitizeAttributes(
      operation.attributes == null
          ? null
          : Map<String, dynamic>.from(operation.attributes!),
      isLineBreak: value is String && value == '\n',
    );
    result.insert(value, sanitized);
  }

  return result;
}

String editorDeltaToCanonicalMarkdown({
  required quill_delta.Delta delta,
  Map<String, String> apiFilesPathToStudioMediaUrl = const <String, String>{},
  Map<String, String> lessonMediaUrlToStudioMediaUrl = const <String, String>{},
}) {
  final sanitized = sanitizeEditorDeltaForCanonicalMarkdown(delta);
  var markdown = lesson_pipeline.createLessonDeltaToMarkdown().convert(
    sanitized,
  );

  if (lesson_pipeline.apiFilesUrlPattern.hasMatch(markdown) &&
      apiFilesPathToStudioMediaUrl.isNotEmpty) {
    markdown = lesson_pipeline.rewriteLessonMarkdownApiFilesUrls(
      markdown: markdown,
      apiFilesPathToStudioMediaUrl: apiFilesPathToStudioMediaUrl,
    );
  }

  if (lessonMediaUrlToStudioMediaUrl.isNotEmpty) {
    markdown = rewriteMarkdownUrls(
      markdown: markdown,
      urlToReplacement: lessonMediaUrlToStudioMediaUrl,
    );
  }

  markdown = canonicalizeSupportedMarkdown(markdown);
  markdown = lesson_pipeline.convertHtmlMediaToTokens(markdown);
  final normalized = lesson_pipeline.normalizeLessonMarkdownForStorage(
    markdown,
  );
  return _stripTerminalDocumentNewline(normalized);
}
