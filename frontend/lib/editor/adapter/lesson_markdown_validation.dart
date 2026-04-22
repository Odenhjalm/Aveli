import 'dart:collection';
import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;

import 'package:aveli/editor/adapter/editor_to_markdown.dart'
    as editor_to_markdown;
import 'package:aveli/editor/adapter/markdown_to_editor.dart'
    as markdown_to_editor;

final RegExp _headingBlankLinesPattern = RegExp(
  r'^(#{1,6}[^\n]*)\n{2,}(?=\S)',
  multiLine: true,
);
final RegExp _listBlankLinesPattern = RegExp(r'\n{2,}(?=(?:[-*+] |\d+\. ))');
final RegExp _nonEmphasisEscapePattern = RegExp(r'\\([!().\-\[\]])');

class LessonMarkdownValidationRoundTripResult {
  const LessonMarkdownValidationRoundTripResult({
    required this.canonicalMarkdown,
    required this.comparisonMarkdown,
    required this.document,
    required this.delta,
  });

  final String canonicalMarkdown;
  final String comparisonMarkdown;
  final quill.Document document;
  final quill_delta.Delta delta;
}

LessonMarkdownValidationRoundTripResult roundTripLessonMarkdownForValidation({
  required String markdown,
  Map<String, String> lessonMediaDocumentLabelsById = const <String, String>{},
}) {
  final document = markdown_to_editor.markdownToEditorDocument(
    markdown: markdown,
    lessonMediaDocumentLabelsById: lessonMediaDocumentLabelsById,
  );
  final delta = document.toDelta();
  final canonicalMarkdown = editor_to_markdown.editorDeltaToCanonicalMarkdown(
    delta: delta,
  );
  return LessonMarkdownValidationRoundTripResult(
    canonicalMarkdown: canonicalMarkdown,
    comparisonMarkdown: normalizeLessonMarkdownForValidationComparison(
      canonicalMarkdown,
    ),
    document: document,
    delta: delta,
  );
}

String normalizeLessonMarkdownForValidationComparison(String markdown) {
  var normalized = markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  normalized = normalized
      .split('\n')
      .map((line) => line.replaceFirst(RegExp(r'[ \t]+$'), ''))
      .join('\n');
  normalized = normalized.replaceAllMapped(_nonEmphasisEscapePattern, (match) {
    return match.group(1) ?? '';
  });
  normalized = normalized.replaceFirst(RegExp(r'\n+$'), '');
  normalized = normalized.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  normalized = normalized.replaceAllMapped(_headingBlankLinesPattern, (match) {
    final headingLine = match.group(1) ?? '';
    return '$headingLine\n';
  });
  normalized = normalized.replaceAll(_listBlankLinesPattern, '\n');
  return normalized;
}

String deltaSemanticSignatureForValidation(quill_delta.Delta delta) {
  final sanitized = editor_to_markdown.sanitizeEditorDeltaForCanonicalMarkdown(
    delta,
  );
  if (sanitized.toList().isEmpty) {
    return '[]';
  }
  final document = quill.Document.fromDelta(sanitized);
  final canonicalOperations = _normalizeSemanticInsertOperations(
    document.root.toDelta(),
  );
  final lines = <Object?>[];
  var segments = <Object?>[];

  void pushText(String text, Map<String, Object?> inlineAttributes) {
    if (text.isEmpty) return;
    final segment = <String, Object?>{'text': text};
    if (inlineAttributes.isNotEmpty) {
      segment['attributes'] = inlineAttributes;
    }
    if (segments.isNotEmpty) {
      final previous = segments.last;
      if (previous is Map<String, Object?> &&
          previous['text'] is String &&
          _stableJson(previous['attributes']) ==
              _stableJson(segment['attributes'])) {
        previous['text'] = '${previous['text']}$text';
        return;
      }
    }
    segments.add(segment);
  }

  void pushEmbed(Object value, Map<String, Object?> inlineAttributes) {
    final segment = <String, Object?>{'embed': _stableJsonValue(value)};
    if (inlineAttributes.isNotEmpty) {
      segment['attributes'] = inlineAttributes;
    }
    segments.add(segment);
  }

  void flushLine(Map<String, Object?> lineAttributes) {
    if (segments.isEmpty && lineAttributes.isEmpty) {
      return;
    }
    final line = <String, Object?>{
      'segments': List<Object?>.unmodifiable(segments),
    };
    if (lineAttributes.isNotEmpty) {
      line['line_attributes'] = lineAttributes;
    }
    lines.add(line);
    segments = <Object?>[];
  }

  for (final operation in canonicalOperations) {
    final inlineAttributes = operation.inlineAttributes;
    final lineAttributes = operation.lineAttributes;
    final value = operation.value;

    if (value is String) {
      final buffer = StringBuffer();
      for (final rune in value.runes) {
        final character = String.fromCharCode(rune);
        if (character == '\n') {
          pushText(buffer.toString(), inlineAttributes);
          buffer.clear();
          flushLine(lineAttributes);
          continue;
        }
        buffer.write(character);
      }
      pushText(buffer.toString(), inlineAttributes);
      continue;
    }

    pushEmbed(value, inlineAttributes);
  }

  if (segments.isNotEmpty) {
    flushLine(const <String, Object?>{});
  }

  return _stableJson(lines);
}

List<_SemanticInsertOperation> _normalizeSemanticInsertOperations(
  quill_delta.Delta delta,
) {
  final rawOperations = delta
      .toList()
      .where((operation) => operation.isInsert)
      .toList();
  while (rawOperations.isNotEmpty) {
    final value = rawOperations.last.value;
    if (value is String && value.isEmpty) {
      rawOperations.removeLast();
      continue;
    }
    break;
  }

  final normalized = <_SemanticInsertOperation>[];
  for (final operation in rawOperations) {
    final normalizedAttributes = _normalizeAttributes(operation.attributes);
    final inlineAttributes = _extractInlineAttributes(normalizedAttributes);
    final lineAttributes = _extractLineAttributes(normalizedAttributes);
    final value = operation.value;

    if (value is String && value.isEmpty) {
      continue;
    }

    if (value is String && normalized.isNotEmpty) {
      final previous = normalized.last;
      if (previous.value is String &&
          _stableJson(previous.inlineAttributes) ==
              _stableJson(inlineAttributes) &&
          _stableJson(previous.lineAttributes) == _stableJson(lineAttributes)) {
        normalized[normalized.length - 1] = _SemanticInsertOperation(
          value: '${previous.value as String}$value',
          inlineAttributes: previous.inlineAttributes,
          lineAttributes: previous.lineAttributes,
        );
        continue;
      }
    }

    normalized.add(
      _SemanticInsertOperation(
        value: value,
        inlineAttributes: inlineAttributes,
        lineAttributes: lineAttributes,
      ),
    );
  }

  return List<_SemanticInsertOperation>.unmodifiable(normalized);
}

Map<String, Object?> _normalizeAttributes(Map<String, dynamic>? attributes) {
  if (attributes == null || attributes.isEmpty) {
    return const <String, Object?>{};
  }

  final normalized = SplayTreeMap<String, Object?>();
  for (final entry in attributes.entries) {
    final value = entry.value;
    if (value == null || value == false) {
      continue;
    }
    normalized[entry.key] = _stableJsonValue(value);
  }
  return Map<String, Object?>.unmodifiable(normalized);
}

Map<String, Object?> _extractInlineAttributes(Map<String, Object?> attributes) {
  if (attributes.isEmpty) {
    return const <String, Object?>{};
  }

  final inline = SplayTreeMap<String, Object?>();
  for (final key in const <String>{'bold', 'italic', 'underline', 'link'}) {
    final value = attributes[key];
    if (value != null) {
      inline[key] = value;
    }
  }
  return Map<String, Object?>.unmodifiable(inline);
}

Map<String, Object?> _extractLineAttributes(Map<String, Object?> attributes) {
  if (attributes.isEmpty) {
    return const <String, Object?>{};
  }

  final line = SplayTreeMap<String, Object?>();
  for (final key in const <String>{'header', 'list', 'indent'}) {
    final value = attributes[key];
    if (value != null) {
      line[key] = value;
    }
  }
  return Map<String, Object?>.unmodifiable(line);
}

Object? _stableJsonValue(Object? value) {
  return switch (value) {
    null => null,
    quill.Embeddable() => _stableJsonValue(value.toJson()),
    Map() => SplayTreeMap<String, Object?>.fromIterable(
      value.keys.map((key) => '$key'),
      value: (key) => _stableJsonValue(value[key]),
    ),
    List() => value.map<Object?>(_stableJsonValue).toList(growable: false),
    _ => value,
  };
}

String _stableJson(Object? value) => jsonEncode(_stableJsonValue(value));

class _SemanticInsertOperation {
  const _SemanticInsertOperation({
    required this.value,
    required this.inlineAttributes,
    required this.lineAttributes,
  });

  final Object value;
  final Map<String, Object?> inlineAttributes;
  final Map<String, Object?> lineAttributes;
}
