import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/editor/session/editor_operation_controller.dart';

void main() {
  EditorOperationQuillController buildController() {
    return EditorOperationQuillController(
      document: quill.Document(),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  EditorOperationReplaceTextRequest replaceRequest({
    required int index,
    required int length,
    required Object data,
    required TextSelection selection,
    bool preserveEmbeds = false,
  }) {
    return EditorOperationReplaceTextRequest(
      index: index,
      length: length,
      data: data,
      selection: selection,
      ignoreFocus: false,
      shouldNotifyListeners: true,
      preserveEmbeds: preserveEmbeds,
    );
  }

  test(
    'replaceText is intercepted until applied through the operation layer',
    () {
      final controller = buildController();
      EditorOperationReplaceTextRequest? intercepted;

      controller.onReplaceTextRequested = (request) {
        intercepted = request;
      };

      controller.replaceText(
        0,
        0,
        'Hello',
        const TextSelection.collapsed(offset: 5),
      );

      expect(intercepted, isNotNull);
      expect(controller.document.toPlainText(), '\n');

      controller.applyReplaceText(intercepted!);

      expect(controller.document.toPlainText(), 'Hello\n');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
    },
  );

  test(
    'replaceTextWithEmbeds is intercepted until applied through the operation layer',
    () {
      final controller = buildController();
      controller.applyReplaceText(
        replaceRequest(
          index: 0,
          length: 0,
          data: 'Before',
          selection: const TextSelection.collapsed(offset: 6),
        ),
      );

      EditorOperationReplaceTextRequest? intercepted;
      controller.onReplaceTextWithEmbedsRequested = (request) {
        intercepted = request;
      };

      controller.replaceTextWithEmbeds(
        0,
        6,
        'After',
        const TextSelection.collapsed(offset: 5),
      );

      expect(intercepted, isNotNull);
      expect(intercepted!.preserveEmbeds, isTrue);
      expect(controller.document.toPlainText(), 'Before\n');

      controller.applyReplaceText(intercepted!);

      expect(controller.document.toPlainText(), 'After\n');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
    },
  );

  test(
    'formatSelection is intercepted until applied through the operation layer',
    () {
      final controller = buildController();
      controller.applyReplaceText(
        replaceRequest(
          index: 0,
          length: 0,
          data: 'Hello',
          selection: const TextSelection.collapsed(offset: 5),
        ),
      );
      controller.applySelection(
        const EditorOperationSelectionRequest(
          selection: TextSelection(baseOffset: 0, extentOffset: 5),
          source: quill.ChangeSource.local,
        ),
      );

      final originalDelta = controller.document.toDelta().toJson();
      EditorOperationFormatTextRequest? intercepted;
      controller.onFormatTextRequested = (request) {
        intercepted = request;
      };

      controller.formatSelection(quill.Attribute.bold);

      expect(intercepted, isNotNull);
      expect(intercepted!.index, 0);
      expect(intercepted!.length, 5);
      expect(intercepted!.attribute, quill.Attribute.bold);
      expect(controller.document.toDelta().toJson(), originalDelta);

      controller.applyFormatText(intercepted!);

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
    },
  );

  test(
    'selection changes are intercepted until applied through the operation layer',
    () {
      final controller = buildController();
      controller.applyReplaceText(
        replaceRequest(
          index: 0,
          length: 0,
          data: 'Hello',
          selection: const TextSelection.collapsed(offset: 5),
        ),
      );

      EditorOperationSelectionRequest? intercepted;
      controller.onSelectionRequested = (request) {
        intercepted = request;
      };

      controller.updateSelection(
        const TextSelection(baseOffset: 1, extentOffset: 4),
        quill.ChangeSource.local,
      );

      expect(intercepted, isNotNull);
      expect(controller.selection, const TextSelection.collapsed(offset: 5));

      controller.applySelection(intercepted!);

      expect(
        controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
    },
  );

  test(
    'undo and redo are intercepted until applied through the operation layer',
    () {
      final controller = buildController();
      controller.applyReplaceText(
        replaceRequest(
          index: 0,
          length: 0,
          data: 'Hello',
          selection: const TextSelection.collapsed(offset: 5),
        ),
      );

      var undoRequests = 0;
      controller.onUndoRequested = () {
        undoRequests += 1;
      };

      controller.undo();

      expect(undoRequests, 1);
      expect(controller.document.toPlainText(), 'Hello\n');

      controller.applyUndo();

      expect(controller.document.toPlainText(), '\n');

      var redoRequests = 0;
      controller.onRedoRequested = () {
        redoRequests += 1;
      };

      controller.redo();

      expect(redoRequests, 1);
      expect(controller.document.toPlainText(), '\n');

      controller.applyRedo();

      expect(controller.document.toPlainText(), 'Hello\n');
    },
  );

  test('unhandled intercepted mutations warn and remain no-op', () {
    final controller = buildController();
    final warnings = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        warnings.add(message);
      }
    };
    addTearDown(() {
      debugPrint = originalDebugPrint;
    });

    controller.replaceText(
      0,
      0,
      'Hello',
      const TextSelection.collapsed(offset: 5),
    );
    controller.replaceTextWithEmbeds(
      0,
      0,
      'Embed',
      const TextSelection.collapsed(offset: 5),
    );
    controller.formatText(0, 1, quill.Attribute.bold);
    controller.formatSelection(quill.Attribute.italic);
    controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 1),
      quill.ChangeSource.local,
    );

    expect(controller.document.toPlainText(), '\n');
    expect(controller.selection, const TextSelection.collapsed(offset: 0));
    expect(
      warnings.where((warning) => warning.contains('[OP CONTROLLER WARNING]')),
      hasLength(5),
    );
    expect(
      warnings,
      contains(contains('method=replaceText handler=unbound action=noop')),
    );
    expect(
      warnings,
      contains(
        contains('method=replaceTextWithEmbeds handler=unbound action=noop'),
      ),
    );
    expect(
      warnings,
      contains(contains('method=formatText handler=unbound action=noop')),
    );
    expect(
      warnings,
      contains(contains('method=formatSelection handler=unbound action=noop')),
    );
    expect(
      warnings,
      contains(contains('method=updateSelection handler=unbound action=noop')),
    );
  });
}
