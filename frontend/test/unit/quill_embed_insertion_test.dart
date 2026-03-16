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
}
