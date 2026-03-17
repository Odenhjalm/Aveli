import 'editor_operation_payloads.dart';

enum EditorOperationType {
  insertText,
  deleteRange,
  replaceRange,
  setSelection,
  loadDocument,
}

class EditorOperation {
  const EditorOperation({
    required this.type,
    required this.baseRevision,
    required this.sessionId,
    required this.payload,
  });

  final EditorOperationType type;
  final int baseRevision;
  final String sessionId;
  final EditorPayload payload;
}
