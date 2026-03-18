void registerAveliEditorTestBridge({
  required void Function(String text) insertText,
  required void Function() backspace,
  required void Function() deleteSelection,
  required void Function(int offset) setCursor,
  required void Function(int start, int end) setSelection,
  required int Function() getCursor,
  required String Function() getDocument,
}) {}

void unregisterAveliEditorTestBridge() {}
