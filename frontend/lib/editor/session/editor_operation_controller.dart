// ignore_for_file: experimental_member_use

import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;

import 'package:aveli/editor/normalization/quill_delta_normalizer.dart'
    show
        stripInlineAttributesForLiveNewlineSanitization,
        styleHasInlineAttributesForLiveNewlineSanitization;

class EditorOperationQuillController extends quill.QuillController {
  EditorOperationQuillController({
    required super.document,
    required super.selection,
    super.config,
    super.keepStyleOnNewLine,
    super.readOnly,
  });

  @override
  void replaceText(
    int index,
    int len,
    Object? data,
    TextSelection? textSelection, {
    bool ignoreFocus = false,
    bool shouldNotifyListeners = true,
  }) {
    if (data is! String || !_shouldSanitizeInlineNewlineInsertion(data)) {
      super.replaceText(
        index,
        len,
        data,
        textSelection,
        ignoreFocus: ignoreFocus,
        shouldNotifyListeners: shouldNotifyListeners,
      );
      return;
    }

    final replaceCallback = onReplaceText;
    if (replaceCallback != null && !replaceCallback(index, len, data)) {
      return;
    }

    final originalCallback = onReplaceText;
    final originalToggledStyle = toggledStyle;
    final newlineToggledStyle = stripInlineAttributesForLiveNewlineSanitization(
      originalToggledStyle,
    );
    final segments = _splitTextByNewline(data);
    onReplaceText = null;

    try {
      if (len > 0) {
        super.replaceText(index, len, '', null, shouldNotifyListeners: false);
      }

      var offset = index;
      for (var i = 0; i < segments.length; i += 1) {
        final segment = segments[i];
        final isLast = i == segments.length - 1;
        toggledStyle = segment == '\n'
            ? newlineToggledStyle
            : originalToggledStyle;
        super.replaceText(
          offset,
          0,
          segment,
          isLast ? textSelection : null,
          ignoreFocus: isLast ? ignoreFocus : false,
          shouldNotifyListeners: isLast ? shouldNotifyListeners : false,
        );
        offset += segment.length;
      }
    } finally {
      onReplaceText = originalCallback;
    }
  }

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

  bool _shouldSanitizeInlineNewlineInsertion(String text) {
    if (!text.contains('\n')) {
      return false;
    }
    return styleHasInlineAttributesForLiveNewlineSanitization(toggledStyle);
  }

  List<String> _splitTextByNewline(String text) {
    final segments = <String>[];
    var segmentStart = 0;
    for (var index = 0; index < text.length; index += 1) {
      if (text.codeUnitAt(index) != 0x0A) {
        continue;
      }
      if (segmentStart < index) {
        segments.add(text.substring(segmentStart, index));
      }
      segments.add('\n');
      segmentStart = index + 1;
    }
    if (segmentStart < text.length) {
      segments.add(text.substring(segmentStart));
    }
    return segments;
  }
}
