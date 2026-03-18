import 'editor_test_bridge_stub.dart'
    if (dart.library.html) 'editor_test_bridge_web.dart'
    as bridge;

void registerAveliEditorTestBridge({
  required void Function(String text) insertText,
  required void Function() backspace,
  required void Function() deleteSelection,
  required void Function(int offset) setCursor,
  required void Function(int start, int end) setSelection,
  required int Function() getCursor,
  required String Function() getDocument,
}) {
  bridge.registerAveliEditorTestBridge(
    insertText: insertText,
    backspace: backspace,
    deleteSelection: deleteSelection,
    setCursor: setCursor,
    setSelection: setSelection,
    getCursor: getCursor,
    getDocument: getDocument,
  );
}

void unregisterAveliEditorTestBridge() {
  bridge.unregisterAveliEditorTestBridge();
}
