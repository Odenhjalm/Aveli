import 'editor_test_bridge_stub.dart'
    if (dart.library.html) 'editor_test_bridge_web.dart'
    as bridge;

void Function(String text)? _insertText;
void Function()? _backspace;
void Function()? _deleteSelection;
void Function(int offset)? _setCursor;
void Function(int start, int end)? _setSelection;
int Function()? _getCursor;
String Function()? _getDocument;
int Function()? _getSelectionStart;
int Function()? _getSelectionEnd;
int Function()? _getControllerIdentity;
int Function()? _getControllerGeneration;
void Function(bool enabled)? _setPreviewMode;

void registerAveliEditorTestBridge({
  required void Function(String text) insertText,
  required void Function() backspace,
  required void Function() deleteSelection,
  required void Function(int offset) setCursor,
  required void Function(int start, int end) setSelection,
  required int Function() getCursor,
  required String Function() getDocument,
  required int Function() getSelectionStart,
  required int Function() getSelectionEnd,
  required int Function() getControllerIdentity,
  required int Function() getControllerGeneration,
  required void Function(bool enabled) setPreviewMode,
}) {
  _insertText = insertText;
  _backspace = backspace;
  _deleteSelection = deleteSelection;
  _setCursor = setCursor;
  _setSelection = setSelection;
  _getCursor = getCursor;
  _getDocument = getDocument;
  _getSelectionStart = getSelectionStart;
  _getSelectionEnd = getSelectionEnd;
  _getControllerIdentity = getControllerIdentity;
  _getControllerGeneration = getControllerGeneration;
  _setPreviewMode = setPreviewMode;
  bridge.registerAveliEditorTestBridge(
    insertText: insertText,
    backspace: backspace,
    deleteSelection: deleteSelection,
    setCursor: setCursor,
    setSelection: setSelection,
    getCursor: getCursor,
    getDocument: getDocument,
    getSelectionStart: getSelectionStart,
    getSelectionEnd: getSelectionEnd,
    getControllerIdentity: getControllerIdentity,
    getControllerGeneration: getControllerGeneration,
    setPreviewMode: setPreviewMode,
  );
}

void unregisterAveliEditorTestBridge() {
  _insertText = null;
  _backspace = null;
  _deleteSelection = null;
  _setCursor = null;
  _setSelection = null;
  _getCursor = null;
  _getDocument = null;
  _getSelectionStart = null;
  _getSelectionEnd = null;
  _getControllerIdentity = null;
  _getControllerGeneration = null;
  _setPreviewMode = null;
  bridge.unregisterAveliEditorTestBridge();
}

void insertText(String text) => _insertText?.call(text);

void backspace() => _backspace?.call();

void deleteSelection() => _deleteSelection?.call();

void setCursor(int offset) => _setCursor?.call(offset);

void setSelection(int start, int end) => _setSelection?.call(start, end);

int? getCursor() => _getCursor?.call();

String? getDocument() => _getDocument?.call();

int? getSelectionStart() => _getSelectionStart?.call();

int? getSelectionEnd() => _getSelectionEnd?.call();

int? getControllerIdentity() => _getControllerIdentity?.call();

int? getControllerGeneration() => _getControllerGeneration?.call();

void setPreviewMode(bool enabled) => _setPreviewMode?.call(enabled);
