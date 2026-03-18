// ignore_for_file: experimental_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

typedef EditorOperationReplaceTextHandler =
    void Function(EditorOperationReplaceTextRequest request);
typedef EditorOperationFormatTextHandler =
    void Function(EditorOperationFormatTextRequest request);
typedef EditorOperationIndentSelectionHandler =
    void Function(EditorOperationIndentSelectionRequest request);
typedef EditorOperationSelectionHandler =
    void Function(EditorOperationSelectionRequest request);

class EditorOperationReplaceTextRequest {
  const EditorOperationReplaceTextRequest({
    required this.index,
    required this.length,
    required this.data,
    required this.selection,
    required this.ignoreFocus,
    required this.shouldNotifyListeners,
    required this.preserveEmbeds,
  });

  final int index;
  final int length;
  final Object? data;
  final TextSelection? selection;
  final bool ignoreFocus;
  final bool shouldNotifyListeners;
  final bool preserveEmbeds;
}

class EditorOperationFormatTextRequest {
  const EditorOperationFormatTextRequest({
    required this.index,
    required this.length,
    required this.attribute,
    required this.shouldNotifyListeners,
  });

  final int index;
  final int length;
  final quill.Attribute? attribute;
  final bool shouldNotifyListeners;
}

class EditorOperationIndentSelectionRequest {
  const EditorOperationIndentSelectionRequest({required this.isIncrease});

  final bool isIncrease;
}

class EditorOperationSelectionRequest {
  const EditorOperationSelectionRequest({
    required this.selection,
    required this.source,
  });

  final TextSelection selection;
  final quill.ChangeSource source;
}

class EditorOperationQuillController extends quill.QuillController {
  EditorOperationQuillController({
    required super.document,
    required super.selection,
    super.config,
    super.keepStyleOnNewLine,
    super.readOnly,
  });

  EditorOperationReplaceTextHandler? onReplaceTextRequested;
  EditorOperationReplaceTextHandler? onReplaceTextWithEmbedsRequested;
  EditorOperationFormatTextHandler? onFormatTextRequested;
  EditorOperationIndentSelectionHandler? onIndentSelectionRequested;
  EditorOperationSelectionHandler? onSelectionRequested;
  VoidCallback? onUndoRequested;
  VoidCallback? onRedoRequested;

  String get _traceControllerId => '$runtimeType#${identityHashCode(this)}';

  void _trace(String prefix, String message) {
    if (!kDebugMode) return;
    debugPrint('$prefix controller=$_traceControllerId $message');
  }

  void _traceOverride(String methodName) {
    _trace('[OP CONTROLLER HIT]', 'method=$methodName');
  }

  void _traceDirectMutation(String methodName, {required String via}) {
    _trace('[QUILL DIRECT MUTATION]', 'method=$methodName via=$via');
  }

  void _warnUnhandledInterceptedMutation(String mutationName) {
    debugPrint(
      '[OP CONTROLLER WARNING] controller=$_traceControllerId '
      'method=$mutationName handler=unbound action=noop',
    );
  }

  void _dispatchInterceptedMutation({
    required String mutationName,
    required Object? handler,
    required VoidCallback dispatchOperation,
  }) {
    if (handler == null) {
      _warnUnhandledInterceptedMutation(mutationName);
      return;
    }
    _trace(
      '[OP CONTROLLER DISPATCH]',
      'method=$mutationName via=operation-handler',
    );
    dispatchOperation();
  }

  void _applyReplaceTextWithEmbedsDirect({
    required int index,
    required int length,
    required String insertedText,
    required TextSelection? selection,
    required bool ignoreFocus,
    required bool shouldNotifyListeners,
  }) {
    final containsEmbed = insertedText.codeUnits.contains(
      quill.Embed.kObjectReplacementInt,
    );
    final normalizedText = containsEmbed
        ? _adjustInsertedTextForEmbeds(insertedText)
        : insertedText;

    super.replaceText(
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
          super.replaceText(localOffset, 0, styleOrEmbed, null);
          continue;
        }

        final style = styleOrEmbed as quill.Style;
        if (style.isInline) {
          for (final attribute in style.values) {
            super.formatText(localOffset, value.length!, attribute);
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

  void applyReplaceText(EditorOperationReplaceTextRequest request) {
    _traceDirectMutation(
      request.preserveEmbeds ? 'replaceTextWithEmbeds' : 'replaceText',
      via: 'applyReplaceText',
    );
    if (request.preserveEmbeds) {
      _applyReplaceTextWithEmbedsDirect(
        index: request.index,
        length: request.length,
        insertedText: request.data as String,
        selection: request.selection,
        ignoreFocus: request.ignoreFocus,
        shouldNotifyListeners: request.shouldNotifyListeners,
      );
      return;
    }
    super.replaceText(
      request.index,
      request.length,
      request.data,
      request.selection,
      ignoreFocus: request.ignoreFocus,
      shouldNotifyListeners: request.shouldNotifyListeners,
    );
  }

  void applyFormatText(EditorOperationFormatTextRequest request) {
    _traceDirectMutation('formatText', via: 'applyFormatText');
    super.formatText(
      request.index,
      request.length,
      request.attribute,
      shouldNotifyListeners: request.shouldNotifyListeners,
    );
  }

  void applyIndentSelection(EditorOperationIndentSelectionRequest request) {
    _traceDirectMutation('indentSelection', via: 'applyIndentSelection');
    if (selection.isCollapsed) {
      final indent = getSelectionStyle().attributes[quill.Attribute.indent.key];
      quill.Attribute? formatAttribute;
      if (indent == null) {
        if (request.isIncrease) {
          formatAttribute = quill.Attribute.indentL1;
        }
      } else if (indent.value == 1 && !request.isIncrease) {
        formatAttribute = quill.Attribute.clone(quill.Attribute.indentL1, null);
      } else if (request.isIncrease) {
        if (indent.value < 5) {
          formatAttribute = quill.Attribute.getIndentLevel(indent.value + 1);
        }
      } else {
        formatAttribute = quill.Attribute.getIndentLevel(indent.value - 1);
      }

      if (formatAttribute != null) {
        super.formatText(
          selection.start,
          selection.end - selection.start,
          formatAttribute,
        );
      }
      return;
    }

    final styles = document.collectAllStylesWithOffset(
      selection.start,
      selection.end - selection.start,
    );
    for (final style in styles) {
      final indent = style.value.attributes[quill.Attribute.indent.key];
      final formatIndex = style.offset > selection.start
          ? style.offset
          : selection.start;
      final formatLength =
          (style.offset + (style.length ?? 0) < selection.end
              ? style.offset + (style.length ?? 0)
              : selection.end) -
          style.offset;
      quill.Attribute? formatAttribute;
      if (indent == null) {
        if (request.isIncrease) {
          formatAttribute = quill.Attribute.indentL1;
        }
      } else if (indent.value == 1 && !request.isIncrease) {
        formatAttribute = quill.Attribute.clone(quill.Attribute.indentL1, null);
      } else if (request.isIncrease) {
        if (indent.value < 5) {
          formatAttribute = quill.Attribute.getIndentLevel(indent.value + 1);
        }
      } else {
        formatAttribute = quill.Attribute.getIndentLevel(indent.value - 1);
      }

      if (formatAttribute != null) {
        document.format(formatIndex, formatLength, formatAttribute);
      }
    }
    notifyListeners();
  }

  void applyUndo() {
    _traceDirectMutation('undo', via: 'applyUndo');
    final result = document.undo();
    if (!result.changed) return;
    applySelection(
      EditorOperationSelectionRequest(
        selection: TextSelection.collapsed(offset: result.len),
        source: quill.ChangeSource.local,
      ),
    );
  }

  void applyRedo() {
    _traceDirectMutation('redo', via: 'applyRedo');
    final result = document.redo();
    if (!result.changed) return;
    applySelection(
      EditorOperationSelectionRequest(
        selection: TextSelection.collapsed(offset: result.len),
        source: quill.ChangeSource.local,
      ),
    );
  }

  void applySelection(EditorOperationSelectionRequest request) {
    _traceDirectMutation('updateSelection', via: 'applySelection');
    super.updateSelection(request.selection, request.source);
  }

  @override
  void replaceText(
    int index,
    int len,
    Object? data,
    TextSelection? textSelection, {
    bool ignoreFocus = false,
    bool shouldNotifyListeners = true,
  }) {
    _traceOverride('replaceText');
    _dispatchInterceptedMutation(
      mutationName: 'replaceText',
      handler: onReplaceTextRequested,
      dispatchOperation: () {
        onReplaceTextRequested!(
          EditorOperationReplaceTextRequest(
            index: index,
            length: len,
            data: data,
            selection: textSelection,
            ignoreFocus: ignoreFocus,
            shouldNotifyListeners: shouldNotifyListeners,
            preserveEmbeds: false,
          ),
        );
      },
    );
  }

  @override
  void replaceTextWithEmbeds(
    int index,
    int len,
    String insertedText,
    TextSelection? textSelection, {
    bool ignoreFocus = false,
    bool shouldNotifyListeners = true,
  }) {
    _traceOverride('replaceTextWithEmbeds');
    _dispatchInterceptedMutation(
      mutationName: 'replaceTextWithEmbeds',
      handler: onReplaceTextWithEmbedsRequested,
      dispatchOperation: () {
        onReplaceTextWithEmbedsRequested!(
          EditorOperationReplaceTextRequest(
            index: index,
            length: len,
            data: insertedText,
            selection: textSelection,
            ignoreFocus: ignoreFocus,
            shouldNotifyListeners: shouldNotifyListeners,
            preserveEmbeds: true,
          ),
        );
      },
    );
  }

  @override
  void formatText(
    int index,
    int len,
    quill.Attribute? attribute, {
    bool shouldNotifyListeners = true,
  }) {
    _traceOverride('formatText');
    _dispatchInterceptedMutation(
      mutationName: 'formatText',
      handler: onFormatTextRequested,
      dispatchOperation: () {
        onFormatTextRequested!(
          EditorOperationFormatTextRequest(
            index: index,
            length: len,
            attribute: attribute,
            shouldNotifyListeners: shouldNotifyListeners,
          ),
        );
      },
    );
  }

  @override
  void formatSelection(
    quill.Attribute? attribute, {
    bool shouldNotifyListeners = true,
  }) {
    _traceOverride('formatSelection');
    _dispatchInterceptedMutation(
      mutationName: 'formatSelection',
      handler: onFormatTextRequested,
      dispatchOperation: () {
        onFormatTextRequested!(
          EditorOperationFormatTextRequest(
            index: selection.start,
            length: selection.end - selection.start,
            attribute: attribute,
            shouldNotifyListeners: shouldNotifyListeners,
          ),
        );
      },
    );
  }

  @override
  void indentSelection(bool isIncrease) {
    _traceOverride('indentSelection');
    _dispatchInterceptedMutation(
      mutationName: 'indentSelection',
      handler: onIndentSelectionRequested,
      dispatchOperation: () {
        onIndentSelectionRequested!(
          EditorOperationIndentSelectionRequest(isIncrease: isIncrease),
        );
      },
    );
  }

  @override
  void undo() {
    _traceOverride('undo');
    _dispatchInterceptedMutation(
      mutationName: 'undo',
      handler: onUndoRequested,
      dispatchOperation: onUndoRequested!,
    );
  }

  @override
  void redo() {
    _traceOverride('redo');
    _dispatchInterceptedMutation(
      mutationName: 'redo',
      handler: onRedoRequested,
      dispatchOperation: onRedoRequested!,
    );
  }

  @override
  void updateSelection(TextSelection textSelection, quill.ChangeSource source) {
    _traceOverride('updateSelection');
    _dispatchInterceptedMutation(
      mutationName: 'updateSelection',
      handler: onSelectionRequested,
      dispatchOperation: () {
        onSelectionRequested!(
          EditorOperationSelectionRequest(
            selection: textSelection,
            source: source,
          ),
        );
      },
    );
  }
}
