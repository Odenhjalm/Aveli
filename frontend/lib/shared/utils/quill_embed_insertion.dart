import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'package:aveli/shared/utils/lesson_content_pipeline.dart'
    as lesson_pipeline;

typedef LessonMediaEmbedReplacementBuilder =
    Object? Function(quill.Embed embed, dynamic currentValue);

TextSelection clampQuillSelection(
  quill.QuillController controller,
  TextSelection selection,
) {
  final maxOffset = max(0, controller.document.length - 1);
  return selection.copyWith(
    baseOffset: selection.baseOffset.clamp(0, maxOffset).toInt(),
    extentOffset: selection.extentOffset.clamp(0, maxOffset).toInt(),
  );
}

/// Normalizes a saved selection so inserts happen inside the editable range.
TextSelection normalizeQuillInsertionSelection(
  quill.QuillController controller,
  TextSelection? selection,
) {
  final maxOffset = max(0, controller.document.length - 1);
  if (selection == null || selection.start < 0 || selection.end < 0) {
    return TextSelection.collapsed(offset: maxOffset);
  }

  return clampQuillSelection(controller, selection);
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

  final collapsed = normalized.copyWith(
    baseOffset: start + (ensureTrailingNewline ? 2 : 1),
    extentOffset: start + (ensureTrailingNewline ? 2 : 1),
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

Object? _defaultLessonMediaEmbedReplacement(
  quill.Embed embed,
  String toLessonMediaId,
) {
  final currentValue = embed.value.data;

  switch (embed.value.type) {
    case lesson_pipeline.AudioBlockEmbed.embedType:
      return lesson_pipeline.AudioBlockEmbed.fromLessonMedia(
        lessonMediaId: toLessonMediaId,
      );
    case quill.BlockEmbed.imageType:
      return quill.BlockEmbed.image(
        lesson_pipeline.imageBlockEmbedValueFromLessonMedia(
          lessonMediaId: toLessonMediaId,
          alt: lesson_pipeline.lessonMediaAltFromEmbedValue(currentValue),
        ),
      );
    case quill.BlockEmbed.videoType:
      return quill.BlockEmbed.video(
        lesson_pipeline.videoBlockEmbedValueFromLessonMedia(
          lessonMediaId: toLessonMediaId,
        ),
      );
    default:
      return null;
  }
}

/// Rewrites lesson media embeds in place so media swaps do not rebuild the
/// entire document or recreate the controller.
bool replaceLessonMediaEmbedsInPlace({
  required quill.QuillController controller,
  required String fromLessonMediaId,
  required String toLessonMediaId,
  TextSelection? selection,
  LessonMediaEmbedReplacementBuilder? replacementBuilder,
}) {
  final normalizedFromLessonMediaId = fromLessonMediaId.trim();
  final normalizedToLessonMediaId = toLessonMediaId.trim();
  if (normalizedFromLessonMediaId.isEmpty ||
      normalizedToLessonMediaId.isEmpty) {
    return false;
  }

  final preservedSelection = clampQuillSelection(
    controller,
    selection ?? controller.selection,
  );
  final replacements = <({int offset, Object embed})>[];
  final documentExtent = max(controller.document.length - 1, 0);
  var offset = 0;

  while (offset < documentExtent) {
    final node = controller.queryNode(offset);
    if (node == null) {
      offset += 1;
      continue;
    }

    final nodeOffset = node.documentOffset;
    if (nodeOffset < offset) {
      offset += 1;
      continue;
    }

    if (node is quill.Embed) {
      final currentValue = node.value.data;
      final currentLessonMediaId = lesson_pipeline.lessonMediaIdFromEmbedValue(
        currentValue,
      );
      if (currentLessonMediaId == normalizedFromLessonMediaId) {
        final replacement =
            replacementBuilder?.call(node, currentValue) ??
            _defaultLessonMediaEmbedReplacement(
              node,
              normalizedToLessonMediaId,
            );
        if (replacement != null) {
          replacements.add((offset: nodeOffset, embed: replacement));
        }
      }
    }

    offset = max(offset + 1, nodeOffset + node.length);
  }

  if (replacements.isEmpty) {
    return false;
  }

  for (final replacement in replacements) {
    controller.replaceText(replacement.offset, 1, replacement.embed, null);
  }

  controller.updateSelection(preservedSelection, quill.ChangeSource.local);
  return true;
}
