import 'package:aveli/editor/session/editor_mutation_pipeline.dart';
import 'package:aveli/editor/session/editor_operation.dart';
import 'package:aveli/editor/session/editor_operation_payloads.dart';
import 'package:aveli/editor/session/editor_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

void main() {
  const uuid = Uuid();

  EditorSession buildSession() {
    return EditorSession(
      sessionId: uuid.v4(),
      lessonId: 'lesson-1',
      controller: quill.QuillController(
        document: quill.Document(),
        selection: const TextSelection.collapsed(offset: 0),
      ),
      focusNode: FocusNode(),
      scrollController: ScrollController(),
      canonicalMarkdown: '',
    );
  }

  void disposeSession(EditorSession session) {
    session.controller.dispose();
    session.focusNode.dispose();
    session.scrollController.dispose();
  }

  test('session identity differs between sessions', () {
    final sessionA = buildSession();
    final sessionB = buildSession();

    expect(sessionA.sessionId, isNot(sessionB.sessionId));

    disposeSession(sessionA);
    disposeSession(sessionB);
  });

  test('revision increments after pipeline mutation', () {
    final session = buildSession();
    final pipeline = EditorMutationPipeline(session);

    pipeline.apply(
      EditorOperation(
        type: EditorOperationType.insertText,
        baseRevision: session.revision,
        sessionId: session.sessionId,
        payload: const InsertTextPayload(
          index: 0,
          text: 'Hej',
          selection: TextSelection.collapsed(offset: 3),
        ),
      ),
    );

    expect(session.revision, 1);
    expect(session.controller.document.toPlainText(), startsWith('Hej'));

    disposeSession(session);
  });

  test('stale operation is ignored', () {
    final session = buildSession();
    final pipeline = EditorMutationPipeline(session);

    pipeline.apply(
      const EditorOperation(
        type: EditorOperationType.insertText,
        baseRevision: 0,
        sessionId: 'stale-session',
        payload: InsertTextPayload(
          index: 0,
          text: 'Hej',
          selection: TextSelection.collapsed(offset: 3),
        ),
      ),
    );

    expect(session.revision, 0);
    expect(session.controller.document.toPlainText(), '\n');

    disposeSession(session);
  });

  test('operation with mismatched revision is ignored', () {
    final session = buildSession();
    final pipeline = EditorMutationPipeline(session);

    pipeline.apply(
      EditorOperation(
        type: EditorOperationType.insertText,
        baseRevision: 999,
        sessionId: session.sessionId,
        payload: const InsertTextPayload(index: 0, text: 'Hej'),
      ),
    );

    expect(session.revision, 0);

    disposeSession(session);
  });
}
