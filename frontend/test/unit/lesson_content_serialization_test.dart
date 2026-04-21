import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/editor/adapter/editor_to_markdown.dart'
    as editor_to_markdown;
import 'package:aveli/editor/adapter/markdown_to_editor.dart'
    as markdown_to_editor;
import 'package:aveli/shared/utils/lesson_content_pipeline.dart';

void main() {
  group('Lesson content serialization', () {
    const lessonMediaId = '123e4567-e89b-12d3-a456-426614174000';

    test('audio embed exports only the canonical lesson media token', () {
      final delta = quill_delta.Delta()
        ..insert('Intro\n')
        ..insert(AudioBlockEmbed.fromLessonMedia(lessonMediaId: lessonMediaId))
        ..insert('\n');

      final markdown = editor_to_markdown.editorDeltaToCanonicalMarkdown(
        delta: delta,
      );

      expect(markdown, contains('!audio($lessonMediaId)'));
      expect(markdown, isNot(contains('://')));
    });

    test('video embed exports only the canonical lesson media token', () {
      final delta = quill_delta.Delta()
        ..insert('Intro\n')
        ..insert(
          quill.BlockEmbed.video(
            videoBlockEmbedValueFromLessonMedia(lessonMediaId: lessonMediaId),
          ),
        )
        ..insert('\n');

      final markdown = editor_to_markdown.editorDeltaToCanonicalMarkdown(
        delta: delta,
      );

      expect(markdown, contains('!video($lessonMediaId)'));
      expect(markdown, isNot(contains('://')));
      expect(markdown, isNot(contains('src')));
    });

    test('image embed exports only the canonical lesson media token', () {
      final delta = quill_delta.Delta()
        ..insert('Intro\n')
        ..insert(
          quill.BlockEmbed.image(
            imageBlockEmbedValueFromLessonMedia(lessonMediaId: lessonMediaId),
          ),
          {quill.Attribute.style.key: 'width: 200; height: 100;'},
        )
        ..insert('\n');

      final markdown = editor_to_markdown.editorDeltaToCanonicalMarkdown(
        delta: delta,
      );

      expect(markdown, contains('!image($lessonMediaId)'));
      expect(markdown, isNot(contains('://')));
      expect(markdown, isNot(contains('width:')));
    });

    test('storage contract rejects raw HTML media tags', () {
      expect(
        () => enforceLessonMarkdownStorageContract(
          '<video controls src="https://cdn.example/video.mp4"></video>',
        ),
        throwsStateError,
      );
    });

    test('storage contract rejects raw markdown media URLs', () {
      expect(
        () => enforceLessonMarkdownStorageContract(
          '![preview](https://cdn.example/image.png)',
        ),
        throwsStateError,
      );
    });

    test('extracts canonical embedded lesson media ids deterministically', () {
      final ids = extractLessonEmbeddedMediaIds('''
!image(image-1)
!audio(audio-1)
!video(video-1)
!document(document-1)
''');

      expect(ids, {'image-1', 'audio-1', 'video-1', 'document-1'});
    });

    test(
      'rich text formatting round-trips through markdown deterministically',
      () {
        final delta = quill_delta.Delta()
          ..insert('Heading')
          ..insert('\n', {quill.Attribute.header.key: 2})
          ..insert('Bold', {quill.Attribute.bold.key: true})
          ..insert(' ')
          ..insert('Italic', {quill.Attribute.italic.key: true})
          ..insert(' ')
          ..insert('Underline', {quill.Attribute.underline.key: true})
          ..insert('\n')
          ..insert('Ordered item')
          ..insert('\n', {quill.Attribute.list.key: 'ordered'})
          ..insert('Bullet item')
          ..insert('\n', {quill.Attribute.list.key: 'bullet'});

        final markdown = editor_to_markdown.editorDeltaToCanonicalMarkdown(
          delta: delta,
        );

        expect(markdown, contains('## Heading'));
        expect(markdown, contains('**Bold**'));
        expect(markdown, contains('*Italic*'));
        expect(markdown, contains('<u>Underline</u>'));
        expect(markdown, contains('1. Ordered item'));
        expect(markdown, contains('- Bullet item'));

        final roundTripped = editor_to_markdown.editorDeltaToCanonicalMarkdown(
          delta: markdown_to_editor
              .markdownToEditorDocument(markdown: markdown)
              .toDelta(),
        );

        expect(roundTripped, markdown);
      },
    );
  });
}
