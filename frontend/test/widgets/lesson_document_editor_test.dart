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

  testWidgets('document preview switches glass and paper reading modes', (
    tester,
  ) async {
    final document = loadLessonDocumentFixtureCorpus().document(
      'full_capability_document',
    );
    final initialJson = document.toCanonicalJsonString();
    var readingMode = LessonDocumentReadingMode.glass;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  LessonDocumentReadingModeToggle(
                    value: readingMode,
                    onChanged: (mode) => setState(() => readingMode = mode),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: LessonDocumentPreview(
                        document: document,
                        readingMode: readingMode,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('lesson_document_paper_reading_surface')),
      findsNothing,
    );
    expect(
      find.text('Full capability document', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.text('Paper'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('lesson_document_paper_reading_surface')),
      findsOneWidget,
    );
    expect(
      find.text('Full capability document', findRichText: true),
      findsOneWidget,
    );
    expect(document.toCanonicalJsonString(), initialJson);

    await tester.tap(find.text('Glass'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('lesson_document_paper_reading_surface')),
      findsNothing,
    );
    expect(document.toCanonicalJsonString(), initialJson);
  });

  testWidgets('document editor toolbar formats only selected text ranges', (
    tester,
  ) async {
    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Alpha Beta Gamma')]),
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

    const fieldKey = ValueKey('lesson_document_editor_block_0');
    await _selectTextRange(
      tester,
      const ValueKey('lesson_document_editor_block_0'),
      text: 'Alpha Beta Gamma',
      start: 6,
      end: 10,
    );
    await _tapToolbar(tester, const Key('lesson_document_toolbar_bold'));

    var paragraph = document.blocks.single as LessonParagraphBlock;
    expect(paragraph.children.map((run) => run.text).toList(), [
      'Alpha ',
      'Beta',
      ' Gamma',
    ]);
    expect(paragraph.children[0].marks, isEmpty);
    expect(paragraph.children[1].marks.map((mark) => mark.type), ['bold']);
    expect(paragraph.children[2].marks, isEmpty);

    await _selectTextRange(
      tester,
      fieldKey,
      text: 'Alpha Beta Gamma',
      start: 6,
      end: 10,
    );
    await _tapToolbar(tester, const Key('lesson_document_toolbar_italic'));
    await _selectTextRange(
      tester,
      fieldKey,
      text: 'Alpha Beta Gamma',
      start: 6,
      end: 10,
    );
    await _tapToolbar(tester, const Key('lesson_document_toolbar_underline'));
    paragraph = document.blocks.single as LessonParagraphBlock;
    final markedTypes = paragraph.children[1].marks
        .map((mark) => mark.type)
        .toSet();
    expect(markedTypes, containsAll(<String>{'bold', 'italic', 'underline'}));
    expect(paragraph.children.first.marks, isEmpty);
    expect(paragraph.children.last.marks, isEmpty);

    await _selectTextRange(
      tester,
      fieldKey,
      text: 'Alpha Beta Gamma',
      start: 6,
      end: 10,
    );
    await _tapToolbar(tester, const Key('lesson_document_toolbar_clear'));
    paragraph = document.blocks.single as LessonParagraphBlock;
    expect(paragraph.children.single.text, 'Alpha Beta Gamma');
    expect(paragraph.children.single.marks, isEmpty);

    await _selectTextRange(
      tester,
      fieldKey,
      text: 'Alpha Beta Gamma',
      start: 6,
      end: 10,
    );
    await _tapToolbar(tester, const Key('lesson_document_toolbar_heading'));
    expect(document.blocks, hasLength(3));
    expect(document.blocks[0], isA<LessonParagraphBlock>());
    expect(
      (document.blocks[0] as LessonParagraphBlock).children.single.text,
      'Alpha ',
    );
    expect(document.blocks[1], isA<LessonHeadingBlock>());
    expect(
      (document.blocks[1] as LessonHeadingBlock).children.single.text,
      'Beta',
    );
    expect(document.blocks[2], isA<LessonParagraphBlock>());
    expect(
      (document.blocks[2] as LessonParagraphBlock).children.single.text,
      ' Gamma',
    );
  });

  testWidgets('document editor ignores toolbar formatting without selection', (
    tester,
  ) async {
    const initial = LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Alpha')]),
      ],
    );
    var document = initial;

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
    await tester.pump();
    await _tapToolbar(tester, const Key('lesson_document_toolbar_bold'));
    await _tapToolbar(tester, const Key('lesson_document_toolbar_heading'));

    expect(document.toJson(), initial.toJson());
  });

  testWidgets('document editor applies list formatting only to selection', (
    tester,
  ) async {
    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Alpha Beta Gamma')]),
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

    await _selectTextRange(
      tester,
      const ValueKey('lesson_document_editor_block_0'),
      text: 'Alpha Beta Gamma',
      start: 6,
      end: 10,
    );
    await _tapToolbar(tester, const Key('lesson_document_toolbar_bullet_list'));

    expect(document.blocks, hasLength(3));
    expect(
      (document.blocks[0] as LessonParagraphBlock).children.single.text,
      'Alpha ',
    );
    expect(document.blocks[1], isA<LessonListBlock>());
    expect(document.blocks[1].type, 'bullet_list');
    expect(
      ((document.blocks[1] as LessonListBlock).items.single.children.single)
          .text,
      'Beta',
    );
    expect(
      (document.blocks[2] as LessonParagraphBlock).children.single.text,
      ' Gamma',
    );
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
    final editorShell = tester.widget<Container>(
      find.byKey(const ValueKey('lesson_document_editor_shell')),
    );
    final shellDecoration = editorShell.decoration as BoxDecoration?;
    expect(shellDecoration?.color, Colors.white);
    final writingSurface = tester.widget<DecoratedBox>(surface);
    final writingSurfaceDecoration = writingSurface.decoration as BoxDecoration;
    expect(writingSurfaceDecoration.color, Colors.white);
    expect(find.textContaining('Dokumentmodell'), findsNothing);
    expect(find.textContaining('lesson_document_v1'), findsNothing);
    expect(find.textContaining('Markdown/Quill'), findsNothing);
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

    await _selectTextRange(
      tester,
      const ValueKey('lesson_document_editor_block_0'),
      text: 'Save me',
      start: 0,
      end: 4,
    );
    await _tapToolbar(tester, const Key('lesson_document_toolbar_bold'));
    await tester.tap(find.byKey(const Key('save_document_payload')));
    await tester.pump();

    expect(savedPayload, isNot(contains('content_markdown')));
    expect(savedPayload, contains('content_document'));
    final savedDocument = LessonDocument.fromJson(
      savedPayload!['content_document'],
    );
    final children =
        (savedDocument.blocks.single as LessonParagraphBlock).children;
    expect(children.first.text, 'Save');
    expect(children.first.marks.single.type, 'bold');
    expect(children.last.text, ' me');
    expect(children.last.marks, isEmpty);
  });
}

Future<void> _selectTextRange(
  WidgetTester tester,
  ValueKey<String> key, {
  required String text,
  required int start,
  required int end,
}) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: start, extentOffset: end),
    ),
  );
  await tester.pump();
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
