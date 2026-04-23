import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/editor/document/lesson_document.dart';
import 'package:aveli/editor/document/lesson_document_editor.dart';

import '../helpers/lesson_document_fixture_corpus.dart';

void main() {
  testWidgets('persisted document preview renders saved media without draft', (
    tester,
  ) async {
    final corpus = loadLessonDocumentFixtureCorpus();
    final savedDocument = corpus.document(
      'persisted_preview_saved_only',
      field: 'saved_document',
    );
    final draftDocument = corpus.document(
      'persisted_preview_saved_only',
      field: 'draft_document',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonDocumentPreview(
            document: savedDocument,
            media: _previewMediaFromCorpus(corpus),
          ),
        ),
      ),
    );

    expect(
      find.text('Persisted corpus content', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Draft-only corpus content', findRichText: true),
      findsNothing,
    );
    expect(find.text('Media: image'), findsOneWidget);
    expect(
      find.textContaining(corpus.mediaRows.first.lessonMediaId),
      findsOneWidget,
    );
    expect(find.textContaining('Corpus image'), findsOneWidget);
    expect(find.textContaining('Status: ready'), findsOneWidget);
    expect(find.text('Persisted CTA'), findsOneWidget);
    expect(savedDocument.toCanonicalJsonString(), isNot(contains('!image(')));
    expect(
      savedDocument.toCanonicalJsonString(),
      isNot(contains('[document](')),
    );
    expect(
      draftDocument.toCanonicalJsonString(),
      contains('Draft-only corpus content'),
    );
  });

  testWidgets('document editor toolbar mutates inline marks and block types', (
    tester,
  ) async {
    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Alpha')]),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                height: 520,
                child: LessonDocumentEditor(
                  document: document,
                  onChanged: (next) => setState(() => document = next),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('lesson_document_editor_block_0')),
    );
    await _tapToolbar(tester, const Key('lesson_document_toolbar_bold'));
    expect(
      (document.blocks.single as LessonParagraphBlock).children.single.marks
          .map((mark) => mark.type),
      contains('bold'),
    );

    await _tapToolbar(tester, const Key('lesson_document_toolbar_italic'));
    await _tapToolbar(tester, const Key('lesson_document_toolbar_underline'));
    final markedTypes = (document.blocks.single as LessonParagraphBlock)
        .children
        .single
        .marks
        .map((mark) => mark.type)
        .toSet();
    expect(markedTypes, containsAll(<String>{'bold', 'italic', 'underline'}));

    await _tapToolbar(tester, const Key('lesson_document_toolbar_clear'));
    await _tapToolbar(tester, const Key('lesson_document_toolbar_heading'));
    expect(document.blocks.single, isA<LessonHeadingBlock>());
    expect(
      (document.blocks.single as LessonHeadingBlock).children.single.marks,
      isEmpty,
    );

    await _tapToolbar(tester, const Key('lesson_document_toolbar_bullet_list'));
    expect(document.blocks.single, isA<LessonListBlock>());
    expect(document.blocks.single.type, 'bullet_list');

    await _tapToolbar(
      tester,
      const Key('lesson_document_toolbar_ordered_list'),
    );
    expect(document.blocks.single, isA<LessonListBlock>());
    expect(document.blocks.single.type, 'ordered_list');
  });

  testWidgets('document editor renders positive corpus authoring nodes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final document = loadLessonDocumentFixtureCorpus().document(
      'full_capability_document',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 1000,
            child: LessonDocumentEditor(document: document, onChanged: (_) {}),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('lesson_document_editor_block_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('lesson_document_editor_block_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('lesson_document_editor_block_2_item_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('lesson_document_editor_block_3_item_0')),
      findsOneWidget,
    );
    await _expectEditorKeyVisible(
      tester,
      const ValueKey('lesson_document_media_4'),
    );
    await _expectEditorKeyVisible(
      tester,
      const ValueKey('lesson_document_media_5'),
    );
    await _expectEditorKeyVisible(
      tester,
      const ValueKey('lesson_document_media_6'),
    );
    await _expectEditorKeyVisible(
      tester,
      const ValueKey('lesson_document_media_7'),
    );
    await _expectEditorKeyVisible(
      tester,
      const ValueKey('lesson_document_cta_label_8'),
    );
    await _expectEditorKeyVisible(
      tester,
      const ValueKey('lesson_document_cta_url_8'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('document editor presents one continuous writing surface', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final document = loadLessonDocumentFixtureCorpus().document(
      'full_capability_document',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 1000,
            child: LessonDocumentEditor(document: document, onChanged: (_) {}),
          ),
        ),
      ),
    );

    final surface = find.byKey(
      const ValueKey('lesson_document_continuous_writing_surface'),
    );

    expect(surface, findsOneWidget);
    expect(
      find.descendant(of: surface, matching: find.byType(Card)),
      findsNothing,
    );
    expect(
      find.descendant(of: surface, matching: find.byType(ListTile)),
      findsNothing,
    );
    expect(
      find.descendant(of: surface, matching: find.text('Formatvisning')),
      findsNothing,
    );
    expect(
      find.descendant(of: surface, matching: find.text('Punktlista')),
      findsNothing,
    );
    expect(
      find.descendant(of: surface, matching: find.text('Numrerad lista')),
      findsNothing,
    );

    final textFields = tester.widgetList<TextField>(
      find.descendant(of: surface, matching: find.byType(TextField)),
    );
    expect(textFields, isNotEmpty);
    for (final field in textFields) {
      expect(field.decoration?.border, same(InputBorder.none));
      expect(field.decoration?.enabledBorder, same(InputBorder.none));
      expect(field.decoration?.focusedBorder, same(InputBorder.none));
    }

    expect(document.toJson()['schema_version'], lessonDocumentSchemaVersion);
    expect(
      document.toCanonicalJsonString(),
      isNot(contains('content_markdown')),
    );
    expect(document.toCanonicalJsonString(), isNot(contains('!image(')));
  });

  testWidgets('document editor edits text without markdown serialization', (
    tester,
  ) async {
    var document = LessonDocument.empty();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 420,
            child: LessonDocumentEditor(
              document: document,
              onChanged: (next) => document = next,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('lesson_document_editor_block_0')),
      'Line one\nLine two',
    );
    await tester.pump();

    expect(document.toJson()['schema_version'], lessonDocumentSchemaVersion);
    expect(document.toCanonicalJsonString(), contains('Line one\\nLine two'));
  });

  testWidgets('document editor save payload is content_document only', (
    tester,
  ) async {
    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Save me')]),
      ],
    );
    Map<String, Object?>? savedPayload;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  SizedBox(
                    height: 420,
                    child: LessonDocumentEditor(
                      document: document,
                      onChanged: (next) => setState(() => document = next),
                    ),
                  ),
                  ElevatedButton(
                    key: const Key('save_document_payload'),
                    onPressed: () {
                      savedPayload = <String, Object?>{
                        'content_document': document.toJson(),
                      };
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('lesson_document_editor_block_0')),
    );
    await _tapToolbar(tester, const Key('lesson_document_toolbar_bold'));
    await tester.tap(find.byKey(const Key('save_document_payload')));
    await tester.pump();

    expect(savedPayload, isNot(contains('content_markdown')));
    expect(savedPayload, contains('content_document'));
    final savedDocument = LessonDocument.fromJson(
      savedPayload!['content_document'],
    );
    expect(
      (savedDocument.blocks.single as LessonParagraphBlock)
          .children
          .single
          .marks
          .single
          .type,
      'bold',
    );
  });
}

Future<void> _tapToolbar(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _expectEditorKeyVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find
          .descendant(
            of: find.byType(LessonDocumentEditor),
            matching: find.byType(Scrollable),
          )
          .last,
      maxScrolls: 20,
    );
  }
  expect(finder, findsOneWidget);
}

List<LessonDocumentPreviewMedia> _previewMediaFromCorpus(
  LessonDocumentFixtureCorpus corpus,
) {
  return [
    for (final row in corpus.mediaRows)
      LessonDocumentPreviewMedia(
        lessonMediaId: row.lessonMediaId,
        mediaType: row.mediaType,
        state: row.state,
        label: row.label,
        resolvedUrl: row.resolvedUrl,
      ),
  ];
}
