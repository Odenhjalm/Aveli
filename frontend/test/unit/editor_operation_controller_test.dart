import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/editor/session/editor_operation_controller.dart';

void main() {
  EditorOperationQuillController buildController() {
    return EditorOperationQuillController(
      document: quill.Document(),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  test('replaceText applies immediately without interception', () {
    final controller = buildController();

    controller.replaceText(
      0,
      0,
      'Hello',
      const TextSelection.collapsed(offset: 5),
    );

    expect(controller.document.toPlainText(), 'Hello\n');
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
  });

  test('replaceText emits an observable local change', () async {
    final controller = buildController();
    final events = <quill.DocChange>[];
    final subscription = controller.changes.listen(events.add);

    controller.replaceText(
      0,
      0,
      'Hello',
      const TextSelection.collapsed(offset: 5),
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(events.single.source, quill.ChangeSource.local);
    expect(events.single.change.toJson(), isNotEmpty);

    await subscription.cancel();
  });

  test(
    'applyDelta composes a local change without recreating the controller',
    () async {
      final controller = buildController();
      final controllerIdentity = identityHashCode(controller);
      final events = <quill.DocChange>[];
      final subscription = controller.changes.listen(events.add);

      controller.applyDelta(
        quill_delta.Delta()..insert('Hello'),
        selection: const TextSelection.collapsed(offset: 5),
      );
      await Future<void>.delayed(Duration.zero);

      expect(identityHashCode(controller), controllerIdentity);
      expect(controller.document.toPlainText(), 'Hello\n');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
      expect(events, hasLength(1));
      expect(events.single.source, quill.ChangeSource.local);
      expect(events.single.change.toJson(), isNotEmpty);

      await subscription.cancel();
    },
  );

  test(
    'applyDelta honors the requested selection with a single UI notification',
    () async {
      final controller = buildController();
      final events = <quill.DocChange>[];
      final subscription = controller.changes.listen(events.add);
      var notifications = 0;
      controller.addListener(() {
        notifications += 1;
      });

      controller.applyDelta(
        quill_delta.Delta()..insert('Hello'),
        selection: const TextSelection.collapsed(offset: 0),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.document.toPlainText(), 'Hello\n');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      expect(events, hasLength(1));
      expect(notifications, 1);

      await subscription.cancel();
    },
  );

  test('replaceTextWithEmbeds applies immediately without interception', () {
    final controller = buildController();
    controller.replaceText(
      0,
      0,
      'Before',
      const TextSelection.collapsed(offset: 6),
    );

    controller.replaceTextWithEmbeds(
      0,
      6,
      'After',
      const TextSelection.collapsed(offset: 5),
    );

    expect(controller.document.toPlainText(), 'After\n');
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
  });

  test('formatSelection applies immediately', () {
    final controller = buildController();
    controller.replaceText(
      0,
      0,
      'Hello',
      const TextSelection.collapsed(offset: 5),
    );
    controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 5),
      quill.ChangeSource.local,
    );

    controller.formatSelection(quill.Attribute.bold);

    final ops = controller.document.toDelta().toJson();
    expect(
      ops.any((op) {
        final attributes = op['attributes'];
        return op['insert'] == 'Hello' &&
            attributes is Map &&
            attributes['bold'] == true;
      }),
      isTrue,
    );
  });

  test('selection changes apply immediately', () {
    final controller = buildController();
    controller.replaceText(
      0,
      0,
      'Hello',
      const TextSelection.collapsed(offset: 5),
    );

    controller.updateSelection(
      const TextSelection(baseOffset: 1, extentOffset: 4),
      quill.ChangeSource.local,
    );

    expect(
      controller.selection,
      const TextSelection(baseOffset: 1, extentOffset: 4),
    );
  });

  test('undo and redo apply immediately', () {
    final controller = buildController();
    controller.replaceText(
      0,
      0,
      'Hello',
      const TextSelection.collapsed(offset: 5),
    );

    controller.undo();

    expect(controller.document.toPlainText(), '\n');

    controller.redo();

    expect(controller.document.toPlainText(), 'Hello\n');
  });
}
