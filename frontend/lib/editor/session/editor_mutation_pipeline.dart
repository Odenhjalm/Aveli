import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;

import 'editor_operation.dart';
import 'editor_operation_payloads.dart';
import 'editor_session.dart';

class EditorMutationPipeline {
  EditorMutationPipeline(this.session);

  final EditorSession session;

  void apply(EditorOperation op) {
    if (op.sessionId != session.sessionId) return;
    if (op.baseRevision != session.revision) return;

    final applied = switch (op.type) {
      EditorOperationType.insertText => _insertText(op),
      EditorOperationType.deleteRange => _deleteRange(op),
      EditorOperationType.replaceRange => _replaceRange(op),
      EditorOperationType.setSelection => _setSelection(op),
      EditorOperationType.loadDocument => _loadDocument(op),
    };

    if (applied) {
      session.incrementRevision();
    }
  }

  bool _insertText(EditorOperation op) {
    if (op.payload is! InsertTextPayload) return false;
    final payload = op.payload as InsertTextPayload;
    session.controller.replaceText(
      payload.index,
      0,
      payload.text,
      payload.selection,
    );
    return true;
  }

  bool _deleteRange(EditorOperation op) {
    if (op.payload is! DeleteRangePayload) return false;
    final payload = op.payload as DeleteRangePayload;
    session.controller.replaceText(
      payload.index,
      payload.length,
      '',
      payload.selection,
    );
    return true;
  }

  bool _replaceRange(EditorOperation op) {
    if (op.payload is! ReplaceRangePayload) return false;
    final payload = op.payload as ReplaceRangePayload;
    final data = payload.data;
    final validData =
        data is String || data is quill.Embeddable || data is quill_delta.Delta;
    if (!validData) return false;
    session.controller.replaceText(
      payload.index,
      payload.length,
      data,
      payload.selection,
    );
    return true;
  }

  bool _setSelection(EditorOperation op) {
    if (op.payload is! SetSelectionPayload) return false;
    final payload = op.payload as SetSelectionPayload;
    session.controller.updateSelection(
      payload.selection,
      quill.ChangeSource.local,
    );
    return true;
  }

  bool _loadDocument(EditorOperation op) {
    if (op.payload is! LoadDocumentPayload) return false;
    final payload = op.payload as LoadDocumentPayload;
    session.controller.document = payload.document;
    return true;
  }
}
