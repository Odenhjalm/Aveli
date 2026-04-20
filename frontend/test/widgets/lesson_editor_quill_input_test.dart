import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/editor/session/editor_operation_controller.dart';

void main() {
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
}
