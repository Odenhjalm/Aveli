import 'package:flutter/foundation.dart';

enum EditorOperationType {
  replaceText,
  formatSelection,
  insertEmbed,
  replaceEmbed,
}

class EditorOperation {
  const EditorOperation({
    required this.type,
    required this.sessionId,
    required this.lessonId,
    required this.baseRevision,
    this.payload,
  });

  final EditorOperationType type;
  final String sessionId;
  final String? lessonId;
  final int baseRevision;
  final Object? payload;
}

enum EditorOperationValidationFailure {
  sessionIdMismatch,
  lessonIdMismatch,
  revisionMismatch,
}

class EditorOperationExecutionResult {
  const EditorOperationExecutionResult.applied({
    required this.didMutate,
    this.nextFingerprint,
  }) : wasApplied = true,
       validationFailure = null;

  const EditorOperationExecutionResult.skipped({
    required this.validationFailure,
  }) : wasApplied = false,
       didMutate = false,
       nextFingerprint = null;

  final bool wasApplied;
  final bool didMutate;
  final String? nextFingerprint;
  final EditorOperationValidationFailure? validationFailure;
}

EditorOperationValidationFailure? validateEditorOperation({
  required String currentSessionId,
  required String? currentLessonId,
  required int currentRevision,
  required EditorOperation operation,
}) {
  if (operation.sessionId != currentSessionId) {
    return EditorOperationValidationFailure.sessionIdMismatch;
  }
  if (operation.lessonId != currentLessonId) {
    return EditorOperationValidationFailure.lessonIdMismatch;
  }
  if (operation.baseRevision != currentRevision) {
    return EditorOperationValidationFailure.revisionMismatch;
  }
  return null;
}

EditorOperationExecutionResult applyGuardedEditorOperation({
  required String currentSessionId,
  required String? currentLessonId,
  required int currentRevision,
  required void Function(int revision) setRevision,
  required EditorOperation operation,
  required String previousFingerprint,
  required String Function() currentFingerprint,
  required VoidCallback apply,
  void Function(String message)? debugLog,
}) {
  final validationFailure = validateEditorOperation(
    currentSessionId: currentSessionId,
    currentLessonId: currentLessonId,
    currentRevision: currentRevision,
    operation: operation,
  );
  if (validationFailure != null) {
    if (kDebugMode) {
      debugLog?.call(
        _editorOperationIgnoredMessage(
          operation: operation,
          validationFailure: validationFailure,
          currentSessionId: currentSessionId,
          currentLessonId: currentLessonId,
          currentRevision: currentRevision,
        ),
      );
    }
    return EditorOperationExecutionResult.skipped(
      validationFailure: validationFailure,
    );
  }

  apply();

  final nextFingerprint = currentFingerprint();
  final didMutate = nextFingerprint != previousFingerprint;
  final nextRevision = didMutate ? operation.baseRevision + 1 : currentRevision;
  if (didMutate) {
    setRevision(nextRevision);
  }

  if (kDebugMode) {
    debugLog?.call(
      '[EditorOperation] type=${operation.type.name} '
      'revision=${operation.baseRevision}->$nextRevision',
    );
  }

  return EditorOperationExecutionResult.applied(
    didMutate: didMutate,
    nextFingerprint: didMutate ? nextFingerprint : null,
  );
}

String _editorOperationIgnoredMessage({
  required EditorOperation operation,
  required EditorOperationValidationFailure validationFailure,
  required String currentSessionId,
  required String? currentLessonId,
  required int currentRevision,
}) {
  switch (validationFailure) {
    case EditorOperationValidationFailure.sessionIdMismatch:
      return '[EditorOperation] ignored type=${operation.type.name} '
          'reason=sessionId mismatch expected=$currentSessionId '
          'actual=${operation.sessionId}';
    case EditorOperationValidationFailure.lessonIdMismatch:
      return '[EditorOperation] ignored type=${operation.type.name} '
          'reason=lessonId mismatch expected=${currentLessonId ?? 'null'} '
          'actual=${operation.lessonId ?? 'null'}';
    case EditorOperationValidationFailure.revisionMismatch:
      return '[EditorOperation] ignored type=${operation.type.name} '
          'reason=baseRevision mismatch expected=$currentRevision '
          'actual=${operation.baseRevision}';
  }
}
