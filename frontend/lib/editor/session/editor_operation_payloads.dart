import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

abstract class EditorPayload {
  const EditorPayload();
}

class InsertTextPayload extends EditorPayload {
  const InsertTextPayload({
    required this.index,
    required this.text,
    this.selection,
  });

  final int index;
  final String text;
  final TextSelection? selection;
}

class DeleteRangePayload extends EditorPayload {
  const DeleteRangePayload({
    required this.index,
    required this.length,
    this.selection,
  });

  final int index;
  final int length;
  final TextSelection? selection;
}

class ReplaceRangePayload extends EditorPayload {
  const ReplaceRangePayload({
    required this.index,
    required this.length,
    required this.data,
    this.selection,
  });

  final int index;
  final int length;
  final Object data;
  final TextSelection? selection;
}

class SetSelectionPayload extends EditorPayload {
  const SetSelectionPayload(this.selection);

  final TextSelection selection;
}

class LoadDocumentPayload extends EditorPayload {
  const LoadDocumentPayload(this.document);

  final quill.Document document;
}
