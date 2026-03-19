import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;
import 'package:markdown/markdown.dart' as md;

import 'package:aveli/shared/utils/lesson_content_pipeline.dart'
    as lesson_pipeline;

final RegExp _strongHtmlPattern = RegExp(
  r'<\s*(strong|b)\s*>(.*?)<\s*/\s*(strong|b)\s*>',
  caseSensitive: false,
  dotAll: true,
);

final RegExp _emphasisHtmlPattern = RegExp(
  r'<\s*(em|i)\s*>(.*?)<\s*/\s*(em|i)\s*>',
  caseSensitive: false,
  dotAll: true,
);

final RegExp _underlineHtmlPattern = RegExp(
  r'<\s*(u|ins)\s*>(.*?)<\s*/\s*(u|ins)\s*>',
  caseSensitive: false,
  dotAll: true,
);

final RegExp _inlineUnderlineTagPattern = RegExp(
  r'<\s*(/?)\s*(u|ins)\s*>',
  caseSensitive: false,
);

final RegExp _escapedBoldItalicPattern = RegExp(
  r'\\\*\\\*\\\*(?=\S)([^\n]+?)(?<=\S)\\\*\\\*\\\*',
  multiLine: true,
);

final RegExp _escapedBoldPattern = RegExp(
  r'\\\*\\\*(?=\S)([^\n]+?)(?<=\S)\\\*\\\*',
  multiLine: true,
);

final RegExp _boldItalicBoldWrappedPattern = RegExp(
  r'\*\*_\s*([^\n]+?)\s*_\*\*',
  multiLine: true,
);

final RegExp _boldItalicItalicWrappedPattern = RegExp(
  r'_\*\*\s*([^\n]+?)\s*\*\*_',
  multiLine: true,
);

final RegExp _spacedBoldItalicPattern = RegExp(
  r'(^|[^*])\*\*\*\s+([^\n]+?)\s+\*\*\*(?=([^*]|$))',
  multiLine: true,
);

final RegExp _spacedBoldPattern = RegExp(
  r'(^|[^*])\*\*\s+([^\n]+?)\s+\*\*(?=([^*]|$))',
  multiLine: true,
);

final RegExp _spacedItalicPattern = RegExp(
  r'(^|[^*])\*\s+([^\n]+?)\s+\*(?=([^*]|$))',
  multiLine: true,
);

final RegExp _doubleUnderscorePattern = RegExp(
  r'(^|[^\w*])__([^\n]+?)__(?=([^\w*]|$))',
  multiLine: true,
);

final RegExp _singleUnderscorePattern = RegExp(
  r'(^|[^\w*])_([^\n]+?)_(?=([^\w*]|$))',
  multiLine: true,
);

md.Document createEditorMarkdownDocument() {
  return md.Document(
    encodeHtml: false,
    extensionSet: md.ExtensionSet.gitHubWeb,
  );
}

String canonicalizeSupportedMarkdown(String markdown) {
  if (markdown.isEmpty) return markdown;

  var canonical = markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  canonical = canonical.replaceAllMapped(_escapedBoldItalicPattern, (match) {
    final body = match.group(1) ?? '';
    return body.isEmpty ? '' : '***$body***';
  });

  canonical = canonical.replaceAllMapped(_escapedBoldPattern, (match) {
    final body = match.group(1) ?? '';
    return body.isEmpty ? '' : '**$body**';
  });

  canonical = canonical.replaceAllMapped(_strongHtmlPattern, (match) {
    final body = (match.group(2) ?? '').trim();
    return body.isEmpty ? '' : '**$body**';
  });

  canonical = canonical.replaceAllMapped(_emphasisHtmlPattern, (match) {
    final body = (match.group(2) ?? '').trim();
    return body.isEmpty ? '' : '*$body*';
  });

  canonical = canonical.replaceAllMapped(_underlineHtmlPattern, (match) {
    final body = (match.group(2) ?? '').trim();
    return body.isEmpty ? '' : '<u>$body</u>';
  });

  canonical = canonical.replaceAllMapped(_boldItalicBoldWrappedPattern, (
    match,
  ) {
    final body = (match.group(1) ?? '').trim();
    return body.isEmpty ? '' : '***$body***';
  });

  canonical = canonical.replaceAllMapped(_boldItalicItalicWrappedPattern, (
    match,
  ) {
    final body = (match.group(1) ?? '').trim();
    return body.isEmpty ? '' : '***$body***';
  });

  canonical = canonical.replaceAllMapped(_spacedBoldItalicPattern, (match) {
    final prefix = match.group(1) ?? '';
    final body = (match.group(2) ?? '').trim();
    return body.isEmpty ? prefix : '$prefix***$body***';
  });

  canonical = canonical.replaceAllMapped(_spacedBoldPattern, (match) {
    final prefix = match.group(1) ?? '';
    final body = (match.group(2) ?? '').trim();
    return body.isEmpty ? prefix : '$prefix**$body**';
  });

  canonical = canonical.replaceAllMapped(_spacedItalicPattern, (match) {
    final prefix = match.group(1) ?? '';
    final body = (match.group(2) ?? '').trim();
    return body.isEmpty ? prefix : '$prefix*$body*';
  });

  canonical = canonical.replaceAllMapped(_doubleUnderscorePattern, (match) {
    final prefix = match.group(1) ?? '';
    final body = (match.group(2) ?? '').trim();
    return body.isEmpty ? prefix : '$prefix**$body**';
  });

  canonical = canonical.replaceAllMapped(_singleUnderscorePattern, (match) {
    final prefix = match.group(1) ?? '';
    final body = (match.group(2) ?? '').trim();
    return body.isEmpty ? prefix : '$prefix*$body*';
  });

  return canonical;
}

String canonicalizeMarkdownForEditor({
  required String markdown,
  Map<String, String> apiFilesPathToStudioMediaUrl = const <String, String>{},
  Map<String, String> lessonMediaDocumentLabelsById = const <String, String>{},
}) {
  if (markdown.trim().isEmpty) {
    return markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  var canonical = markdown;
  if (lesson_pipeline.apiFilesUrlPattern.hasMatch(canonical) &&
      apiFilesPathToStudioMediaUrl.isNotEmpty) {
    canonical = lesson_pipeline.rewriteLessonMarkdownApiFilesUrls(
      markdown: canonical,
      apiFilesPathToStudioMediaUrl: apiFilesPathToStudioMediaUrl,
    );
  }

  canonical = canonicalizeSupportedMarkdown(canonical);
  canonical = lesson_pipeline.rewriteLessonMarkdownDocumentLinksForEditor(
    markdown: canonical,
    lessonMediaDocumentLabelsById: lessonMediaDocumentLabelsById,
  );
  return canonical;
}

quill_delta.Delta markdownToEditorDelta({
  required String markdown,
  Map<String, String> apiFilesPathToStudioMediaUrl = const <String, String>{},
  Map<String, String> lessonMediaDocumentLabelsById = const <String, String>{},
  md.Document? markdownDocument,
}) {
  final canonical = canonicalizeMarkdownForEditor(
    markdown: markdown,
    apiFilesPathToStudioMediaUrl: apiFilesPathToStudioMediaUrl,
    lessonMediaDocumentLabelsById: lessonMediaDocumentLabelsById,
  );
  final converter = lesson_pipeline.createLessonMarkdownToDelta(
    markdownDocument ?? createEditorMarkdownDocument(),
  );
  final delta = lesson_pipeline.convertLessonMarkdownToDelta(
    converter,
    canonical,
  );
  return _applySupportedInlineHtml(delta);
}

quill_delta.Delta _applySupportedInlineHtml(quill_delta.Delta source) {
  final result = quill_delta.Delta();
  var underlineDepth = 0;

  void insertText(String text, Map<String, dynamic>? attributes) {
    if (text.isEmpty) return;
    final nextAttributes = attributes == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(attributes);
    if (underlineDepth > 0) {
      nextAttributes[quill.Attribute.underline.key] = true;
    }
    result.insert(text, nextAttributes.isEmpty ? null : nextAttributes);
  }

  for (final operation in source.toList()) {
    if (!operation.isInsert) {
      result.push(operation);
      continue;
    }

    final attributes = operation.attributes == null
        ? null
        : Map<String, dynamic>.from(operation.attributes!);
    final value = operation.value;
    if (value is! String) {
      result.insert(value, attributes);
      continue;
    }

    final matches = _inlineUnderlineTagPattern.allMatches(value).toList();
    if (matches.isEmpty) {
      insertText(value, attributes);
      continue;
    }

    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        insertText(value.substring(cursor, match.start), attributes);
      }

      final rawTag = match.group(0) ?? '';
      final isClosing = (match.group(1) ?? '').isNotEmpty;
      if (isClosing) {
        if (underlineDepth > 0) {
          underlineDepth -= 1;
        } else {
          insertText(rawTag, attributes);
        }
      } else {
        underlineDepth += 1;
      }
      cursor = match.end;
    }

    if (cursor < value.length) {
      insertText(value.substring(cursor), attributes);
    }
  }

  return result;
}

quill_delta.Delta _canonicalizeDeltaForQuillDocument(quill_delta.Delta delta) {
  if (delta.toList().isEmpty) {
    return delta;
  }

  final document = quill.Document.fromDelta(delta);
  return document.root.toDelta();
}

quill.Document markdownToEditorDocument({
  required String markdown,
  Map<String, String> apiFilesPathToStudioMediaUrl = const <String, String>{},
  Map<String, String> lessonMediaDocumentLabelsById = const <String, String>{},
  md.Document? markdownDocument,
}) {
  final delta = markdownToEditorDelta(
    markdown: markdown,
    apiFilesPathToStudioMediaUrl: apiFilesPathToStudioMediaUrl,
    lessonMediaDocumentLabelsById: lessonMediaDocumentLabelsById,
    markdownDocument: markdownDocument,
  );
  if (delta.toList().isEmpty) {
    return quill.Document();
  }
  return quill.Document.fromDelta(_canonicalizeDeltaForQuillDocument(delta));
}
