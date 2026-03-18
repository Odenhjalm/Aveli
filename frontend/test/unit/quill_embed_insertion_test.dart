import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'package:aveli/shared/utils/lesson_content_pipeline.dart'
    as lesson_pipeline;
import 'package:aveli/shared/utils/quill_embed_insertion.dart';

void main() {
  test('replaceSelectionWithBlockEmbed clamps stale end selection safely', () {
    final controller = quill.QuillController.basic();
    controller.replaceText(
      0,
      0,
      'Intro',
      const TextSelection.collapsed(offset: 5),
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
      final controller = quill.QuillController.basic();
      controller.replaceText(
        0,
        0,
        'Intro',
        const TextSelection.collapsed(offset: 5),
      );
      controller.updateSelection(
        const TextSelection.collapsed(offset: 5),
        quill.ChangeSource.local,
      );
      controller.formatSelection(quill.Attribute.bold);

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
    final controller = quill.QuillController.basic();
    controller.replaceText(
      0,
      0,
      'Intro\n',
      const TextSelection.collapsed(offset: 6),
    );
    replaceSelectionWithBlockEmbed(
      controller: controller,
      embed: lesson_pipeline.AudioBlockEmbed.fromLessonMedia(
        lessonMediaId: 'audio-old',
        src: 'https://cdn.test/audio-old.mp3',
      ),
      selection: const TextSelection.collapsed(offset: 6),
    );
    controller.replaceText(
      controller.document.length - 1,
      0,
      'Eftertext',
      TextSelection.collapsed(offset: controller.document.length - 1 + 9),
    );

    final originalControllerIdentity = identityHashCode(controller);
    const preservedSelection = TextSelection.collapsed(offset: 2);
    controller.updateSelection(preservedSelection, quill.ChangeSource.local);

    final changed = replaceLessonMediaEmbedsInPlace(
      controller: controller,
      fromLessonMediaId: 'audio-old',
      toLessonMediaId: 'audio-new',
      selection: preservedSelection,
      replacementBuilder: (embed, _) =>
          lesson_pipeline.AudioBlockEmbed.fromLessonMedia(
            lessonMediaId: 'audio-new',
            src: 'https://cdn.test/audio-new.mp3',
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
    expect(
      lesson_pipeline.lessonMediaUrlFromEmbedValue(embedValue),
      'https://cdn.test/audio-new.mp3',
    );
  });

  test('replaceText keeps controller stable for mixed text and embeds', () {
    final controller = quill.QuillController.basic();
    controller.replaceText(
      0,
      0,
      'Intro\n',
      const TextSelection.collapsed(offset: 6),
    );
    replaceSelectionWithBlockEmbed(
      controller: controller,
      embed: quill.BlockEmbed.image(
        lesson_pipeline.imageBlockEmbedValueFromLessonMedia(
          lessonMediaId: 'media-image-1',
          src: 'https://cdn.test/media-image-1.webp',
        ),
      ),
      selection: const TextSelection.collapsed(offset: 6),
    );
    final appendOffset = controller.document.length - 1;
    controller.replaceText(
      appendOffset,
      0,
      'Eftertext',
      TextSelection.collapsed(offset: appendOffset + 9),
    );

    final originalControllerIdentity = identityHashCode(controller);
    final insertOffset = controller.document.length - 1;

    controller.replaceText(
      insertOffset,
      0,
      ' hej',
      TextSelection.collapsed(offset: insertOffset + 4),
    );

    expect(identityHashCode(controller), originalControllerIdentity);
    expect(controller.document.toPlainText(), contains('Eftertext hej\n'));

    controller.replaceText(
      insertOffset,
      4,
      '',
      TextSelection.collapsed(offset: insertOffset),
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
      final controller = quill.QuillController.basic();
      controller.replaceText(
        0,
        0,
        'Intro',
        const TextSelection.collapsed(offset: 5),
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
