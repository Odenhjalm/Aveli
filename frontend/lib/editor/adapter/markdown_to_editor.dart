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

  canonical = canonical.replaceAllMapped(_strongHtmlPattern, (match) {
    final body = (match.group(2) ?? '').trim();
    return body.isEmpty ? '' : '**$body**';
  });

  canonical = canonical.replaceAllMapped(_emphasisHtmlPattern, (match) {
    final body = (match.group(2) ?? '').trim();
    return body.isEmpty ? '' : '*$body*';
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
  return canonical;
}

quill_delta.Delta markdownToEditorDelta({
  required String markdown,
  Map<String, String> apiFilesPathToStudioMediaUrl = const <String, String>{},
  md.Document? markdownDocument,
}) {
  final canonical = canonicalizeMarkdownForEditor(
    markdown: markdown,
    apiFilesPathToStudioMediaUrl: apiFilesPathToStudioMediaUrl,
  );
  final converter = lesson_pipeline.createLessonMarkdownToDelta(
    markdownDocument ?? createEditorMarkdownDocument(),
  );
  return lesson_pipeline.convertLessonMarkdownToDelta(converter, canonical);
}

quill.Document markdownToEditorDocument({
  required String markdown,
  Map<String, String> apiFilesPathToStudioMediaUrl = const <String, String>{},
  md.Document? markdownDocument,
}) {
  final delta = markdownToEditorDelta(
    markdown: markdown,
    apiFilesPathToStudioMediaUrl: apiFilesPathToStudioMediaUrl,
    markdownDocument: markdownDocument,
  );
  if (delta.toList().isEmpty) {
    return quill.Document();
  }
  return quill.Document.fromDelta(delta);
}
