import 'dart:math';

import 'package:flutter/services.dart';

bool isPdfLinkEditorLine(String lineText) {
  final trimmed = lineText.trim();
  if (!trimmed.startsWith('📄 ')) return false;
  return trimmed.toLowerCase().contains('.pdf');
}

TextRange? findPdfLinkDeletionRange({
  required String plainText,
  required int cursorOffset,
  required bool forward,
}) {
  if (plainText.isEmpty) return null;

  final normalizedOffset = cursorOffset.clamp(0, plainText.length);
  final candidateOffsets = <int>{
    min(normalizedOffset, max(0, plainText.length - 1)),
    max(0, normalizedOffset - 1),
    min(max(0, plainText.length - 1), normalizedOffset + 1),
  }.toList(growable: false)..sort();

  for (final candidate in candidateOffsets) {
    final range = _lineRangeAt(plainText, candidate);
    if (range == null) continue;

    final lineText = plainText
        .substring(range.start, range.end)
        .replaceAll('\n', '');
    if (!isPdfLinkEditorLine(lineText)) continue;

    final touchesCurrentLine =
        normalizedOffset >= range.start && normalizedOffset <= range.end;
    final touchesPreviousBoundary = !forward && normalizedOffset == range.end;
    final touchesNextBoundary =
        forward && range.start > 0 && normalizedOffset == range.start - 1;

    if (touchesCurrentLine || touchesPreviousBoundary || touchesNextBoundary) {
      return range;
    }
  }

  return null;
}

TextRange? _lineRangeAt(String plainText, int offset) {
  if (plainText.isEmpty) return null;
  final normalizedOffset = offset.clamp(0, max(0, plainText.length - 1)) as int;

  var lineStart = normalizedOffset;
  while (lineStart > 0 && plainText[lineStart - 1] != '\n') {
    lineStart -= 1;
  }

  var lineEnd = normalizedOffset;
  while (lineEnd < plainText.length && plainText[lineEnd] != '\n') {
    lineEnd += 1;
  }
  if (lineEnd < plainText.length) {
    lineEnd += 1;
  }

  return TextRange(start: lineStart, end: lineEnd);
}
