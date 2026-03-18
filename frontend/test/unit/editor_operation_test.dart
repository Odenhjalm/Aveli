import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/editor/session/editor_operation.dart';

void main() {
  EditorOperation buildOperation({
    String sessionId = 'session-1',
    String? lessonId = 'lesson-1',
    int baseRevision = 3,
  }) {
    return EditorOperation(
      type: EditorOperationType.replaceText,
      sessionId: sessionId,
      lessonId: lessonId,
      baseRevision: baseRevision,
    );
  }

  group('applyGuardedEditorOperation', () {
    test('operation ignored if sessionId mismatch', () {
      var currentRevision = 3;
      var document = 'before';
      var applyCalled = false;
      final logMessages = <String>[];

      final result = applyGuardedEditorOperation(
        currentSessionId: 'session-1',
        currentLessonId: 'lesson-1',
        currentRevision: currentRevision,
        setRevision: (revision) => currentRevision = revision,
        operation: buildOperation(sessionId: 'session-2'),
        previousFingerprint: document,
        currentFingerprint: () => document,
        debugLog: logMessages.add,
        apply: () {
          applyCalled = true;
          document = 'after';
        },
      );

      expect(result.wasApplied, isFalse);
      expect(
        result.validationFailure,
        EditorOperationValidationFailure.sessionIdMismatch,
      );
      expect(result.didMutate, isFalse);
      expect(applyCalled, isFalse);
      expect(document, 'before');
      expect(currentRevision, 3);
      expect(logMessages, hasLength(1));
      expect(logMessages.single, contains('sessionId mismatch'));
    });

    test('operation ignored if lessonId mismatch', () {
      var currentRevision = 3;
      var document = 'before';
      var applyCalled = false;
      final logMessages = <String>[];

      final result = applyGuardedEditorOperation(
        currentSessionId: 'session-1',
        currentLessonId: 'lesson-1',
        currentRevision: currentRevision,
        setRevision: (revision) => currentRevision = revision,
        operation: buildOperation(lessonId: 'lesson-2'),
        previousFingerprint: document,
        currentFingerprint: () => document,
        debugLog: logMessages.add,
        apply: () {
          applyCalled = true;
          document = 'after';
        },
      );

      expect(result.wasApplied, isFalse);
      expect(
        result.validationFailure,
        EditorOperationValidationFailure.lessonIdMismatch,
      );
      expect(result.didMutate, isFalse);
      expect(applyCalled, isFalse);
      expect(document, 'before');
      expect(currentRevision, 3);
      expect(logMessages, hasLength(1));
      expect(logMessages.single, contains('lessonId mismatch'));
    });

    test('operation ignored if revision mismatch', () {
      var currentRevision = 3;
      var document = 'before';
      var applyCalled = false;
      final logMessages = <String>[];

      final result = applyGuardedEditorOperation(
        currentSessionId: 'session-1',
        currentLessonId: 'lesson-1',
        currentRevision: currentRevision,
        setRevision: (revision) => currentRevision = revision,
        operation: buildOperation(baseRevision: 4),
        previousFingerprint: document,
        currentFingerprint: () => document,
        debugLog: logMessages.add,
        apply: () {
          applyCalled = true;
          document = 'after';
        },
      );

      expect(result.wasApplied, isFalse);
      expect(
        result.validationFailure,
        EditorOperationValidationFailure.revisionMismatch,
      );
      expect(result.didMutate, isFalse);
      expect(applyCalled, isFalse);
      expect(document, 'before');
      expect(currentRevision, 3);
      expect(logMessages, hasLength(1));
      expect(logMessages.single, contains('baseRevision mismatch'));
    });

    test('valid operations still apply correctly', () {
      var currentRevision = 3;
      var document = 'before';
      var applyCalled = false;
      final logMessages = <String>[];

      final result = applyGuardedEditorOperation(
        currentSessionId: 'session-1',
        currentLessonId: 'lesson-1',
        currentRevision: currentRevision,
        setRevision: (revision) => currentRevision = revision,
        operation: buildOperation(),
        previousFingerprint: document,
        currentFingerprint: () => document,
        debugLog: logMessages.add,
        apply: () {
          applyCalled = true;
          document = 'after';
        },
      );

      expect(result.wasApplied, isTrue);
      expect(result.validationFailure, isNull);
      expect(result.didMutate, isTrue);
      expect(result.nextFingerprint, 'after');
      expect(applyCalled, isTrue);
      expect(document, 'after');
      expect(currentRevision, 4);
      expect(logMessages, hasLength(1));
      expect(logMessages.single, contains('revision=3->4'));
    });
  });
}
