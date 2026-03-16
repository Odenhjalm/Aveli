import 'dart:js_interop';
import 'dart:js_util' as js_util;
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

Object? _bridgeObject;

void registerAveliEditorTestBridge({
  required void Function(String text) insertText,
  required void Function() backspace,
  required void Function() deleteSelection,
  required void Function(int offset) setCursor,
  required void Function(int start, int end) setSelection,
  required int Function() getCursor,
  required String Function() getDocument,
}) {
  final bridge = js_util.newObject();

  js_util.setProperty(
    bridge,
    'insertText',
    ((String text) {
      insertText(text);
    }).toJS,
  );

  js_util.setProperty(
    bridge,
    'backspace',
    (() {
      backspace();
    }).toJS,
  );

  js_util.setProperty(
    bridge,
    'deleteBackward',
    (() {
      backspace();
    }).toJS,
  );

  js_util.setProperty(
    bridge,
    'deleteSelection',
    (() {
      deleteSelection();
    }).toJS,
  );

  js_util.setProperty(
    bridge,
    'setCursor',
    ((int offset) {
      setCursor(offset);
    }).toJS,
  );

  js_util.setProperty(
    bridge,
    'setSelection',
    ((int start, int end) {
      setSelection(start, end);
    }).toJS,
  );

  js_util.setProperty(
    bridge,
    'getCursor',
    (() {
      return getCursor();
    }).toJS,
  );

  js_util.setProperty(
    bridge,
    'getDocument',
    (() {
      return getDocument();
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
