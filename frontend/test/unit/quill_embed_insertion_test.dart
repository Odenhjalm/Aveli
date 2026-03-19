import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'package:aveli/editor/session/editor_operation_controller.dart';
import 'package:aveli/shared/utils/lesson_content_pipeline.dart'
    as lesson_pipeline;
import 'package:aveli/shared/utils/quill_embed_insertion.dart';

void main() {
  EditorOperationQuillController buildController() {
    return EditorOperationQuillController(
      document: quill.Document(),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  void applyReplaceText(
    EditorOperationQuillController controller, {
    required int index,
    required int length,
    required Object data,
    required TextSelection selection,
  }) {
    controller.replaceText(index, length, data, selection);
  }

  void applySelection(
    EditorOperationQuillController controller,
    TextSelection selection,
  ) {
    controller.updateSelection(selection, quill.ChangeSource.local);
  }

  void applyFormatSelection(
    EditorOperationQuillController controller,
    quill.Attribute attribute,
  ) {
    controller.formatText(
      controller.selection.start,
      controller.selection.end - controller.selection.start,
      attribute,
    );
  }

  test('replaceSelectionWithBlockEmbed clamps stale end selection safely', () {
    final controller = buildController();
    applyReplaceText(
      controller,
      index: 0,
      length: 0,
      data: 'Intro',
      selection: const TextSelection.collapsed(offset: 5),
    );

    expect(
      () => replaceSelectionWithBlockEmbed(
        controller: controller,
        embed: quill.BlockEmbed.image('https://cdn.test/uploaded.webp'),
        selection: TextSelection.collapsed(offset: controller.document.length),
      ),
      returnsNormally,
    );

    final markdown = lesson_pipeline.createLessonDeltaToMarkdown().convert(
      controller.document.toDelta(),
    );
    expect(markdown, contains('![](https://cdn.test/uploaded.webp)'));
  });

  test(
    'replaceSelectionWithBlockEmbed ignores toggled inline styles for embeds',
    () {
      final controller = buildController();
      applyReplaceText(
        controller,
        index: 0,
        length: 0,
        data: 'Intro',
        selection: const TextSelection.collapsed(offset: 5),
      );
      applySelection(controller, const TextSelection.collapsed(offset: 5));
      applyFormatSelection(controller, quill.Attribute.bold);

      expect(
        () => replaceSelectionWithBlockEmbed(
          controller: controller,
          embed: quill.BlockEmbed.image('https://cdn.test/bold-image.webp'),
          selection: controller.selection,
        ),
        returnsNormally,
      );

      final markdown = lesson_pipeline.createLessonDeltaToMarkdown().convert(
        controller.document.toDelta(),
      );
      expect(markdown, contains('![](https://cdn.test/bold-image.webp)'));
      expect(controller.toggledStyle.attributes, contains('bold'));
    },
  );

  test('replaceLessonMediaEmbedsInPlace swaps audio embeds locally', () {
    final controller = buildController();
    applyReplaceText(
      controller,
      index: 0,
      length: 0,
      data: 'Intro\n',
      selection: const TextSelection.collapsed(offset: 6),
    );
    replaceSelectionWithBlockEmbed(
      controller: controller,
      embed: lesson_pipeline.AudioBlockEmbed.fromLessonMedia(
        lessonMediaId: 'audio-old',
      ),
      selection: const TextSelection.collapsed(offset: 6),
    );
    applyReplaceText(
      controller,
      index: controller.document.length - 1,
      length: 0,
      data: 'Eftertext',
      selection: TextSelection.collapsed(
        offset: controller.document.length - 1 + 9,
      ),
    );

    final originalControllerIdentity = identityHashCode(controller);
    const preservedSelection = TextSelection.collapsed(offset: 2);
    applySelection(controller, preservedSelection);

    final changed = replaceLessonMediaEmbedsInPlace(
      controller: controller,
      fromLessonMediaId: 'audio-old',
      toLessonMediaId: 'audio-new',
      selection: preservedSelection,
      replacementBuilder: (embed, _) =>
          lesson_pipeline.AudioBlockEmbed.fromLessonMedia(
            lessonMediaId: 'audio-new',
          ),
    );

    expect(changed, isTrue);
    expect(identityHashCode(controller), originalControllerIdentity);
    expect(controller.selection, preservedSelection);

    final markdown = lesson_pipeline.createLessonDeltaToMarkdown().convert(
      controller.document.toDelta(),
    );
    expect(markdown, contains('!audio(audio-new)'));
    expect(markdown, isNot(contains('audio-old')));

    final embedNode = controller.queryNode(6);
    expect(embedNode, isA<quill.Embed>());
    final embedValue = (embedNode! as quill.Embed).value.data;
    expect(lesson_pipeline.lessonMediaUrlFromEmbedValue(embedValue), isNull);
  });

  test('replaceText keeps controller stable for mixed text and embeds', () {
    final controller = buildController();
    applyReplaceText(
      controller,
      index: 0,
      length: 0,
      data: 'Intro\n',
      selection: const TextSelection.collapsed(offset: 6),
    );
    replaceSelectionWithBlockEmbed(
      controller: controller,
      embed: quill.BlockEmbed.image(
        lesson_pipeline.imageBlockEmbedValueFromLessonMedia(
          lessonMediaId: 'media-image-1',
        ),
      ),
      selection: const TextSelection.collapsed(offset: 6),
    );
    final appendOffset = controller.document.length - 1;
    applyReplaceText(
      controller,
      index: appendOffset,
      length: 0,
      data: 'Eftertext',
      selection: TextSelection.collapsed(offset: appendOffset + 9),
    );

    final originalControllerIdentity = identityHashCode(controller);
    final insertOffset = controller.document.length - 1;

    applyReplaceText(
      controller,
      index: insertOffset,
      length: 0,
      data: ' hej',
      selection: TextSelection.collapsed(offset: insertOffset + 4),
    );

    expect(identityHashCode(controller), originalControllerIdentity);
    expect(controller.document.toPlainText(), contains('Eftertext hej\n'));

    applyReplaceText(
      controller,
      index: insertOffset,
      length: 4,
      data: '',
      selection: TextSelection.collapsed(offset: insertOffset),
    );

    expect(identityHashCode(controller), originalControllerIdentity);

    final markdown = lesson_pipeline.createLessonDeltaToMarkdown().convert(
      controller.document.toDelta(),
    );
    expect(markdown, contains('!image(media-image-1)'));
    expect(markdown, contains('Eftertext'));
    expect(markdown, isNot(contains('Eftertext hej')));
  });

  test(
    'replaceLessonMediaEmbedsInPlace is a no-op when media id is absent',
    () {
      final controller = buildController();
      applyReplaceText(
        controller,
        index: 0,
        length: 0,
        data: 'Intro',
        selection: const TextSelection.collapsed(offset: 5),
      );
      final originalDelta = controller.document.toDelta().toJson();

      final changed = replaceLessonMediaEmbedsInPlace(
        controller: controller,
        fromLessonMediaId: 'missing-id',
        toLessonMediaId: 'new-id',
      );

      expect(changed, isFalse);
      expect(controller.document.toDelta().toJson(), originalDelta);
    },
  );
}
