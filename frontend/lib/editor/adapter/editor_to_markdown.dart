import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;
import 'package:markdown_quill/markdown_quill.dart';

import 'package:aveli/editor/adapter/markdown_to_editor.dart'
    show canonicalizeSupportedMarkdown;
import 'package:aveli/shared/utils/lesson_content_pipeline.dart'
    as lesson_pipeline;

const Set<String> _allowedInlineAttributeKeys = <String>{
  'bold',
  'italic',
  'underline',
  'link',
};

final RegExp _escapedUnderlineTagPattern = RegExp(r'\\<(/?)u\\>');
const String _canonicalItalicMarkdownDelimiter = '*';

String _stripTerminalDocumentNewline(String markdown) {
  return markdown.replaceFirst(RegExp(r'\n+$'), '');
}

String _restoreSupportedInlineHtml(String markdown) {
  if (!markdown.contains(r'\<')) return markdown;
  return markdown.replaceAllMapped(_escapedUnderlineTagPattern, (match) {
    final slash = match.group(1) ?? '';
    return '<${slash}u>';
  });
}

Never _throwCanonicalMediaWriteViolation(String raw) {
  throw StateError(
    'Canonical text contract violation: media refs must use typed '
    'lesson_media ids. Could not accept $raw.',
  );
}

void _writeCanonicalLessonMediaToken({
  required String kind,
  required Object? rawValue,
  required StringSink output,
}) {
  final lessonMediaId = lesson_pipeline.lessonMediaIdFromEmbedValue(rawValue);
  if (lessonMediaId != null && lessonMediaId.isNotEmpty) {
    output.write('!$kind($lessonMediaId)');
    return;
  }
  _throwCanonicalMediaWriteViolation('$rawValue');
}

DeltaToMarkdown _createCanonicalLessonDeltaToMarkdown() {
  return DeltaToMarkdown(
    customEmbedHandlers: {
      lesson_pipeline.AudioBlockEmbed.embedType: (embed, output) {
        _writeCanonicalLessonMediaToken(
          kind: 'audio',
          rawValue: embed.value.data,
          output: output,
        );
      },
      quill.BlockEmbed.imageType: (embed, output) {
        _writeCanonicalLessonMediaToken(
          kind: 'image',
          rawValue: embed.value.data,
          output: output,
        );
      },
      quill.BlockEmbed.videoType: (embed, output) {
        _writeCanonicalLessonMediaToken(
          kind: 'video',
          rawValue: embed.value.data,
          output: output,
        );
      },
    },
    customTextAttrsHandlers: {
      quill.Attribute.italic.key: CustomAttributeHandler(
        beforeContent: (attribute, node, output) {
          if (node.previous?.style.containsKey(attribute.key) != true) {
            output.write(_canonicalItalicMarkdownDelimiter);
          }
        },
        afterContent: (attribute, node, output) {
          if (node.next?.style.containsKey(attribute.key) != true) {
            output.write(_canonicalItalicMarkdownDelimiter);
          }
        },
      ),
    },
  );
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

quill_delta.Delta _expandUnderlineAttributesForMarkdown(
  quill_delta.Delta source,
) {
  final result = quill_delta.Delta();

  void insertValue(Object value, Map<String, dynamic>? attributes) {
    result.insert(
      value,
      attributes == null || attributes.isEmpty ? null : attributes,
    );
  }

  void insertUnderlinedText(String text, Map<String, dynamic>? attributes) {
    if (text.isEmpty) return;

    var cursor = 0;
    while (cursor <= text.length) {
      final newlineIndex = text.indexOf('\n', cursor);
      final end = newlineIndex == -1 ? text.length : newlineIndex;
      final chunk = text.substring(cursor, end);
      if (chunk.isNotEmpty) {
        insertValue('<u>', attributes);
        insertValue(chunk, attributes);
        insertValue('</u>', attributes);
      }
      if (newlineIndex == -1) {
        break;
      }
      insertValue('\n', attributes);
      cursor = newlineIndex + 1;
    }
  }

  for (final operation in source.toList()) {
    if (!operation.isInsert) {
      result.push(operation);
      continue;
    }

    final rawAttributes = operation.attributes == null
        ? null
        : Map<String, dynamic>.from(operation.attributes!);
    final isUnderlined = rawAttributes?[quill.Attribute.underline.key] == true;
    rawAttributes?.remove(quill.Attribute.underline.key);
    final attributes = rawAttributes == null || rawAttributes.isEmpty
        ? null
        : rawAttributes;

    final value = operation.value;
    if (!isUnderlined || value is! String || value.isEmpty) {
      insertValue(value, attributes);
      continue;
    }

    insertUnderlinedText(value, attributes);
  }

  return result;
}

String editorDeltaToCanonicalMarkdown({
  required quill_delta.Delta delta,
  bool enforceStorageContract = true,
}) {
  final sanitized = sanitizeEditorDeltaForCanonicalMarkdown(delta);
  final markdownReady = _expandUnderlineAttributesForMarkdown(sanitized);
  var markdown = _createCanonicalLessonDeltaToMarkdown().convert(markdownReady);
  markdown = _restoreSupportedInlineHtml(markdown);
  markdown = canonicalizeSupportedMarkdown(markdown);
  if (enforceStorageContract) {
    final markdownWithContract = lesson_pipeline
        .enforceLessonMarkdownStorageContract(markdown);
    return _stripTerminalDocumentNewline(markdownWithContract);
  }
  return _stripTerminalDocumentNewline(markdown);
}
