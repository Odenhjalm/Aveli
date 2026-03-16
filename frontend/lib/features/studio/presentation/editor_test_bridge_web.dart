import 'dart:js_interop';
import 'dart:js_util' as js_util;
import 'dart:math' as math;

import 'package:flutter/material.dart' show TextSelection;
import 'package:flutter_quill/flutter_quill.dart' as quill;
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

Object? _bridgeObject;

void registerAveliEditorTestBridge(
  quill.QuillController? Function() controllerAccessor,
) {
  final bridge = js_util.newObject();

  js_util.setProperty(
    bridge,
    'insertText',
    ((String text) {
      final controller = controllerAccessor();
      if (controller == null) return;

      final replacementRange = _currentReplacementRange(controller);
      controller.replaceText(
        replacementRange.start,
        replacementRange.length,
        text,
        TextSelection.collapsed(offset: replacementRange.start + text.length),
      );
    }).toJS,
  );

  js_util.setProperty(
    bridge,
    'backspace',
    (() {
      final controller = controllerAccessor();
      if (controller == null) return;

      _deleteBackward(controller);
    }).toJS,
  );

  js_util.setProperty(
    bridge,
    'deleteBackward',
    (() {
      final controller = controllerAccessor();
      if (controller == null) return;

      _deleteBackward(controller);
    }).toJS,
  );

  js_util.setProperty(
    bridge,
    'deleteSelection',
    (() {
      final controller = controllerAccessor();
      if (controller == null) return;

      final replacementRange = _currentReplacementRange(controller);
      if (replacementRange.length <= 0) return;

      controller.replaceText(
        replacementRange.start,
        replacementRange.length,
        '',
        TextSelection.collapsed(offset: replacementRange.start),
      );
    }).toJS,
  );

  js_util.setProperty(
    bridge,
    'setCursor',
    ((int offset) {
      final controller = controllerAccessor();
      if (controller == null) return;

      final collapsedOffset = _clampOffset(controller, offset);
      controller.updateSelection(
        TextSelection.collapsed(offset: collapsedOffset),
        quill.ChangeSource.local,
      );
    }).toJS,
  );

  js_util.setProperty(
    bridge,
    'setSelection',
    ((int start, int end) {
      final controller = controllerAccessor();
      if (controller == null) return;

      controller.updateSelection(
        TextSelection(
          baseOffset: _clampOffset(controller, start),
          extentOffset: _clampOffset(controller, end),
        ),
        quill.ChangeSource.local,
      );
    }).toJS,
  );

  js_util.setProperty(
    bridge,
    'getCursor',
    (() {
      final controller = controllerAccessor();
      if (controller == null) return 0;

      return _clampOffset(controller, controller.selection.baseOffset);
    }).toJS,
  );

  js_util.setProperty(
    bridge,
    'getDocument',
    (() {
      final controller = controllerAccessor();
      if (controller == null) return '';

      return controller.document.toPlainText();
    }).toJS,
  );

  js_util.setProperty(web.window, 'aveliTestBridge', bridge);
  _bridgeObject = bridge;
}

void unregisterAveliEditorTestBridge() {
  if (_bridgeObject == null) return;
  js_util.setProperty(web.window, 'aveliTestBridge', null);
  _bridgeObject = null;
}

_ReplacementRange _currentReplacementRange(quill.QuillController controller) {
  final selection = controller.selection;
  final documentExtent = _documentExtent(controller);

  if (!selection.isValid) {
    return _ReplacementRange(start: documentExtent, length: 0);
  }

  final start =
      math.min(selection.start, selection.end).clamp(0, documentExtent) as int;
  final end =
      math.max(selection.start, selection.end).clamp(0, documentExtent) as int;
  return _ReplacementRange(start: start, length: end - start);
}

void _deleteBackward(quill.QuillController controller) {
  final replacementRange = _currentReplacementRange(controller);
  if (replacementRange.length > 0) {
    controller.replaceText(
      replacementRange.start,
      replacementRange.length,
      '',
      TextSelection.collapsed(offset: replacementRange.start),
    );
    return;
  }

  if (replacementRange.start <= 0) return;

  controller.replaceText(
    replacementRange.start - 1,
    1,
    '',
    TextSelection.collapsed(offset: replacementRange.start - 1),
  );
}

int _documentExtent(quill.QuillController controller) {
  return math.max(controller.document.length - 1, 0);
}

int _clampOffset(quill.QuillController controller, int offset) {
  return offset.clamp(0, _documentExtent(controller)) as int;
}

final class _ReplacementRange {
  const _ReplacementRange({required this.start, required this.length});

  final int start;
  final int length;
}
