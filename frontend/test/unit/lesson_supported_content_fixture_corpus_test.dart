import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/editor/adapter/editor_to_markdown.dart'
    as editor_to_markdown;
import 'package:aveli/editor/adapter/markdown_to_editor.dart'
    as markdown_to_editor;

import '../helpers/lesson_supported_content_fixture_corpus.dart';

void main() {
  group('Lesson supported-content fixture corpus', () {
    late JsonMap corpus;

    setUpAll(() {
      corpus = loadLessonSupportedContentFixtureCorpus();
    });

    test(
      'loads the authoritative corpus and required frontend binding groups',
      () {
        expect(corpus['status'], 'ACTIVE');
        expect(
          bindingGroup(corpus, 'frontend_adapter_tests'),
          isA<Map<String, dynamic>>(),
        );
        expect(
          bindingGroup(corpus, 'frontend_newline_tests'),
          isA<Map<String, dynamic>>(),
        );
        expect(
          bindingGroup(corpus, 'frontend_guard_tests'),
          isA<Map<String, dynamic>>(),
        );
        expect(
          bindingGroup(corpus, 'preview_learner_parity_tests'),
          isA<Map<String, dynamic>>(),
        );
      },
    );

    test('locks formerly blocked fixtures for blank lines and inline documents', () {
      final newlineFixture = supportedCanonicalFixture(
        corpus,
        'paragraph_blank_line_two_paragraphs',
      );
      final documentFixture = supportedCanonicalFixture(
        corpus,
        'document_token_inline',
      );

      expect(newlineFixture['status'], 'locked');
      expect(
        stringListField(newlineFixture, 'binding_groups'),
        contains('frontend_newline_tests'),
      );

      expect(documentFixture['status'], 'locked');
      expect(
        stringListField(documentFixture, 'binding_groups'),
        contains('preview_learner_parity_tests'),
      );
    });

    test('bound frontend paths referenced by the corpus exist in the repo', () {
      for (final groupId in <String>[
        'frontend_adapter_tests',
        'frontend_newline_tests',
        'frontend_guard_tests',
        'preview_learner_parity_tests',
      ]) {
        final group = bindingGroup(corpus, groupId);
        for (final path in stringListField(group, 'runtime_paths')) {
          expect(repoRelativeFile(path).existsSync(), isTrue, reason: path);
        }
        for (final path in stringListField(group, 'test_paths')) {
          expect(repoRelativeFile(path).existsSync(), isTrue, reason: path);
        }
      }
    });

    test(
      'nonblocked adapter fixtures round-trip through the active adapter boundary',
      () {
        final adapterGroup = bindingGroup(corpus, 'frontend_adapter_tests');
        for (final fixtureId in stringListField(adapterGroup, 'fixture_ids')) {
          final fixture = supportedCanonicalFixture(corpus, fixtureId);
          if ('${fixture['status']}' != 'locked') {
            continue;
          }

          final markdown = '${fixture['canonical_markdown']}';
          final document = markdown_to_editor.markdownToEditorDocument(
            markdown: markdown,
          );
          final serialized = editor_to_markdown.editorDeltaToCanonicalMarkdown(
            delta: document.toDelta(),
          );

          expect(serialized, markdown, reason: fixtureId);
        }
      },
    );
  });
}
