import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// Normalizes a saved selection so inserts happen inside the editable range.
TextSelection normalizeQuillInsertionSelection(
  quill.QuillController controller,
  TextSelection? selection,
) {
  final maxOffset = max(0, controller.document.length - 1);
  if (selection == null || selection.start < 0 || selection.end < 0) {
    return TextSelection.collapsed(offset: maxOffset);
  }

  final baseOffset = selection.baseOffset.clamp(0, maxOffset);
  final extentOffset = selection.extentOffset.clamp(0, maxOffset);
  return TextSelection(baseOffset: baseOffset, extentOffset: extentOffset);
}

/// Inserts a block embed in a single replaceText step to avoid transient
/// invalid document states during multi-step editor updates.
TextSelection replaceSelectionWithBlockEmbed({
  required quill.QuillController controller,
  required Object embed,
  TextSelection? selection,
  bool ensureTrailingNewline = true,
}) {
  final normalized = normalizeQuillInsertionSelection(controller, selection);
  final start = min(normalized.start, normalized.end);
  final end = max(normalized.start, normalized.end);

  final previousToggledStyle = controller.toggledStyle;
  controller.toggledStyle = const quill.Style();

  final collapsed = TextSelection.collapsed(
    offset: start + (ensureTrailingNewline ? 2 : 1),
  );
  try {
    controller.replaceText(
      start,
      end - start,
      embed,
      TextSelection.collapsed(offset: start + 1),
    );
    if (ensureTrailingNewline) {
      controller.replaceText(start + 1, 0, '\n', collapsed);
    }
  } finally {
    controller.toggledStyle = const quill.Style();
  }

  controller.updateSelection(collapsed, quill.ChangeSource.local);
  if (previousToggledStyle.isNotEmpty) {
    controller.toggledStyle = previousToggledStyle;
  }
  return collapsed;
}
