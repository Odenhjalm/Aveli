import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/editor/session/editor_operation_controller.dart';

void main() {
  List<Map<String, Object?>> newlineAttributes(
    EditorOperationQuillController controller,
  ) {
    return [
      for (final op in controller.document.toDelta().toJson())
        if (op['insert'] == '\n')
          Map<String, Object?>.from(
            (op['attributes'] as Map?)?.cast<String, Object?>() ??
                const <String, Object?>{},
          ),
    ];
  }

  bool hasStyledInsert(
    EditorOperationQuillController controller, {
    required String text,
    required String key,
    required Object? value,
  }) {
    return controller.document.toDelta().toJson().any((op) {
      if (op['insert'] != text) {
        return false;
      }
      final attributes =
          (op['attributes'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{};
      return attributes[key] == value;
    });
  }

  testWidgets(
    'Quill editor accepts ordinary text input through TextInputClient',
    (tester) async {
      final controller = EditorOperationQuillController(
        document: quill.Document(),
        selection: const TextSelection.collapsed(offset: 0),
      );
      final focusNode = FocusNode();
      final scrollController = ScrollController();

      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 320,
              child: quill.QuillEditor.basic(
                controller: controller,
                focusNode: focusNode,
                scrollController: scrollController,
                config: const quill.QuillEditorConfig(
                  minHeight: 280,
                  padding: EdgeInsets.all(16),
                ),
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'hello\n',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();

      expect(controller.document.toPlainText(), 'hello\n');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
    },
  );

  testWidgets(
    'Quill editor keeps inline styles off live newline insertions in heading and styled-line flow',
    (tester) async {
      final controller = EditorOperationQuillController(
        document: quill.Document.fromDelta(
          quill_delta.Delta()
            ..insert('Heading3')
            ..insert('\n', {quill.Attribute.header.key: 3}),
        ),
        selection: const TextSelection.collapsed(offset: 8),
      );
      final focusNode = FocusNode();
      final scrollController = ScrollController();

      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 320,
              child: quill.QuillEditor.basic(
                controller: controller,
                focusNode: focusNode,
                scrollController: scrollController,
                config: const quill.QuillEditorConfig(
                  minHeight: 280,
                  padding: EdgeInsets.all(16),
                ),
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Heading3\n\n',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      controller.updateSelection(
        const TextSelection.collapsed(offset: 9),
        quill.ChangeSource.local,
      );
      controller.formatSelection(quill.Attribute.bold);
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Heading3\nBold\n',
          selection: TextSelection.collapsed(offset: 13),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Heading3\nBold\n\n',
          selection: TextSelection.collapsed(offset: 14),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      controller.updateSelection(
        const TextSelection.collapsed(offset: 14),
        quill.ChangeSource.local,
      );
      controller.formatSelection(quill.Attribute.italic);
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Heading3\nBold\nItalic\n',
          selection: TextSelection.collapsed(offset: 20),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      expect(controller.document.toPlainText(), 'Heading3\nBold\nItalic\n');
      expect(
        newlineAttributes(
          controller,
        ).any((attributes) => attributes[quill.Attribute.header.key] == 3),
        isTrue,
      );
      expect(
        newlineAttributes(controller).every(
          (attributes) =>
              !attributes.containsKey(quill.Attribute.bold.key) &&
              !attributes.containsKey(quill.Attribute.italic.key) &&
              !attributes.containsKey(quill.Attribute.underline.key) &&
              !attributes.containsKey(quill.Attribute.link.key),
        ),
        isTrue,
      );
      expect(
        hasStyledInsert(
          controller,
          text: 'Bold',
          key: quill.Attribute.bold.key,
          value: true,
        ),
        isTrue,
      );
      expect(
        hasStyledInsert(
          controller,
          text: 'Italic',
          key: quill.Attribute.italic.key,
          value: true,
        ),
        isTrue,
      );
    },
  );
}
