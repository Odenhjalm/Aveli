// ignore_for_file: experimental_member_use

import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;

class EditorOperationQuillController extends quill.QuillController {
  EditorOperationQuillController({
    required super.document,
    required super.selection,
    super.config,
    super.keepStyleOnNewLine,
    super.readOnly,
  });

  /// Applies a delta directly to the active controller without rebuilding it.
  void applyDelta(quill_delta.Delta delta, {required TextSelection selection}) {
    final shouldCompose = delta.isNotEmpty;
    final shouldUpdateSelection = this.selection != selection;
    if (!shouldCompose && !shouldUpdateSelection) return;

    if (shouldCompose) {
      document.compose(delta, quill.ChangeSource.local);
    }
    if (shouldUpdateSelection) {
      updateSelection(selection, quill.ChangeSource.local);
      return;
    }

    // `document.compose` updates the document stream but not the controller
    // listeners that drive the editor subtree, so emit one UI refresh here.
    notifyListeners();
  }

  /// Preserves pasted embed/style metadata while still mutating Quill directly.
  @override
  void replaceTextWithEmbeds(
    int index,
    int length,
    String insertedText,
    TextSelection? selection, {
    bool ignoreFocus = false,
    bool shouldNotifyListeners = true,
  }) {
    final containsEmbed = insertedText.codeUnits.contains(
      quill.Embed.kObjectReplacementInt,
    );
    final normalizedText = containsEmbed
        ? _adjustInsertedTextForEmbeds(insertedText)
        : insertedText;

    replaceText(
      index,
      length,
      normalizedText,
      selection,
      ignoreFocus: ignoreFocus,
      shouldNotifyListeners: shouldNotifyListeners,
    );

    if ((normalizedText == pastePlainText && pastePlainText.isNotEmpty) ||
        containsEmbed) {
      for (final value in pasteStyleAndEmbed) {
        final localOffset = index + value.offset;
        final styleOrEmbed = value.value;
        if (styleOrEmbed is quill.Embeddable) {
          replaceText(localOffset, 0, styleOrEmbed, null);
          continue;
        }

        final style = styleOrEmbed as quill.Style;
        if (style.isInline) {
          for (final attribute in style.values) {
            formatText(localOffset, value.length!, attribute);
          }
          continue;
        }

        if (style.isBlock) {
          final node = document.queryChild(localOffset).node;
          if (node != null && value.length == node.length - 1) {
            for (final attribute in style.values) {
              document.format(localOffset, 0, attribute);
            }
          }
        }
      }
    }
  }

  String _adjustInsertedTextForEmbeds(String text) {
    final buffer = StringBuffer();
    for (var index = 0; index < text.length; index += 1) {
      if (text.codeUnitAt(index) == quill.Embed.kObjectReplacementInt) {
        continue;
      }
      buffer.writeCharCode(text.codeUnitAt(index));
    }
    return buffer.toString();
  }
}
