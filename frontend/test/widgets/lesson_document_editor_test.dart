import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/editor/document/lesson_document.dart';
import 'package:aveli/editor/document/lesson_document_editor.dart';
import 'package:aveli/shared/widgets/inline_audio_player.dart';

import '../helpers/fake_home_audio_engine.dart';
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
    expect(find.text('Infogad media'), findsOneWidget);
    expect(
      find.textContaining(corpus.mediaRows.first.lessonMediaId),
      findsNothing,
    );
    expect(
      find.textContaining(corpus.mediaRows.first.mediaAssetId),
      findsNothing,
    );
    expect(find.text('Media: image'), findsNothing);
    expect(find.textContaining('Corpus image'), findsOneWidget);
    expect(find.textContaining('Status: ready'), findsNothing);
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

  testWidgets('document preview fallback hides media metadata', (tester) async {
    const lessonMediaId = '99999999-9999-4999-8999-999999999999';
    const document = LessonDocument(
      blocks: [
        LessonMediaBlock(mediaType: 'image', lessonMediaId: lessonMediaId),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LessonDocumentPreview(
            document: document,
            media: [
              LessonDocumentPreviewMedia(
                lessonMediaId: lessonMediaId,
                mediaType: 'image',
                state: 'ready',
                resolvedUrl: 'https://cdn.test/image.webp',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Infogad media'), findsOneWidget);
    expect(find.text('Sparad media'), findsOneWidget);
    expect(find.textContaining(lessonMediaId), findsNothing);
    expect(find.textContaining('Media: image'), findsNothing);
    expect(find.textContaining('Status: ready'), findsNothing);
    expect(find.textContaining('media_type'), findsNothing);

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, double.infinity);
    expect(image.height, isNull);
    expect(image.fit, BoxFit.contain);
  });

  testWidgets('document preview fallback renders audio playback controls', (
    tester,
  ) async {
    const lessonMediaId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const audioUrl = 'https://cdn.test/audio.mp3';
    final engineFactory = FakeHomeAudioEngineFactory();
    const document = LessonDocument(
      blocks: [
        LessonMediaBlock(mediaType: 'audio', lessonMediaId: lessonMediaId),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonDocumentPreview(
            document: document,
            audioEngineFactory: engineFactory.create,
            media: const [
              LessonDocumentPreviewMedia(
                lessonMediaId: lessonMediaId,
                mediaType: 'audio',
                state: 'ready',
                label: 'narration.mp3',
                resolvedUrl: audioUrl,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Infogad media'), findsOneWidget);
    expect(find.textContaining('narration.mp3'), findsOneWidget);
    expect(find.byType(InlineAudioPlayer), findsOneWidget);
    expect(find.byType(InlineAudioPlayerView), findsOneWidget);
    final player = tester.widget<InlineAudioPlayer>(
      find.byType(InlineAudioPlayer),
    );
    expect(player.url, audioUrl);
    expect(player.title, 'narration.mp3');
    expect(player.minimalUi, isTrue);
    expect(engineFactory.createCount, 1);
    expect(engineFactory.single.loadedUrls, orderedEquals([audioUrl]));
  });

  testWidgets('document preview fallback leaves document media presentation', (
    tester,
  ) async {
    const lessonMediaId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    const document = LessonDocument(
      blocks: [
        LessonMediaBlock(mediaType: 'document', lessonMediaId: lessonMediaId),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LessonDocumentPreview(
            document: document,
            media: [
              LessonDocumentPreviewMedia(
                lessonMediaId: lessonMediaId,
                mediaType: 'document',
                state: 'ready',
                label: 'handout.pdf',
                resolvedUrl: 'https://cdn.test/handout.pdf',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Infogad media'), findsOneWidget);
    expect(find.textContaining('handout.pdf'), findsOneWidget);
    expect(find.textContaining(lessonMediaId), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(InlineAudioPlayer), findsNothing);
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

  testWidgets('document editor exposes active position for media insertion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Intro')]),
        LessonParagraphBlock(children: [LessonTextRun('Outro')]),
      ],
    );
    int? insertionIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              void insertMedia(String mediaType, String lessonMediaId) {
                final index = insertionIndex ?? document.blocks.length;
                setState(() {
                  document = document.insertMedia(
                    index,
                    mediaType: mediaType,
                    lessonMediaId: lessonMediaId,
                  );
                  insertionIndex = index + 1;
                });
              }

              return Column(
                children: [
                  SizedBox(
                    height: 520,
                    child: LessonDocumentEditor(
                      document: document,
                      onChanged: (next) => setState(() => document = next),
                      onInsertionIndexChanged: (index) {
                        insertionIndex = index;
                      },
                    ),
                  ),
                  ElevatedButton(
                    key: const Key('insert_image_at_editor_position'),
                    onPressed: () => insertMedia(
                      'image',
                      '55555555-5555-4555-8555-555555555555',
                    ),
                    child: const Text('Insert image'),
                  ),
                  ElevatedButton(
                    key: const Key('insert_audio_at_editor_position'),
                    onPressed: () => insertMedia(
                      'audio',
                      '66666666-6666-4666-8666-666666666666',
                    ),
                    child: const Text('Insert audio'),
                  ),
                  Expanded(
                    child: LessonDocumentPreview(
                      key: const ValueKey<String>('positioned_media_preview'),
                      document: document,
                    ),
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
      text: 'Intro',
      start: 0,
      end: 5,
    );
    await tester.tap(find.byKey(const Key('insert_image_at_editor_position')));
    await tester.pump();

    expect(_blockTypes(document), ['paragraph', 'media', 'paragraph']);
    expect(
      (document.blocks[0] as LessonParagraphBlock).children.single.text,
      'Intro',
    );
    expect(
      (document.blocks[2] as LessonParagraphBlock).children.single.text,
      'Outro',
    );
    final imageBlock = document.blocks[1] as LessonMediaBlock;
    expect(imageBlock.mediaType, 'image');
    expect(imageBlock.lessonMediaId, '55555555-5555-4555-8555-555555555555');
    final preview = tester.widget<LessonDocumentPreview>(
      find.byKey(const ValueKey<String>('positioned_media_preview')),
    );
    expect(preview.document.toJson(), document.toJson());

    await tester.tap(
      find.byKey(const ValueKey('lesson_document_editor_block_2')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('insert_audio_at_editor_position')));
    await tester.pump();

    expect(_blockTypes(document), ['paragraph', 'media', 'paragraph', 'media']);
    expect(
      (document.blocks[2] as LessonParagraphBlock).children.single.text,
      'Outro',
    );
    final audioBlock = document.blocks[3] as LessonMediaBlock;
    expect(audioBlock.mediaType, 'audio');
    expect(audioBlock.lessonMediaId, '66666666-6666-4666-8666-666666666666');
  });

  testWidgets('document editor moves media blocks deterministically', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Intro')]),
        LessonMediaBlock(
          mediaType: 'image',
          lessonMediaId: '77777777-7777-4777-8777-777777777777',
        ),
        LessonParagraphBlock(children: [LessonTextRun('Outro')]),
      ],
    );
    int? insertionIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  SizedBox(
                    height: 520,
                    child: LessonDocumentEditor(
                      document: document,
                      onChanged: (next) => setState(() => document = next),
                      onInsertionIndexChanged: (index) {
                        insertionIndex = index;
                      },
                    ),
                  ),
                  Expanded(
                    child: LessonDocumentPreview(
                      key: const ValueKey<String>('moved_media_preview'),
                      document: document,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    IconButton moveUpButton(int index) {
      return tester.widget<IconButton>(
        find.byKey(ValueKey<String>('lesson_document_media_move_up_$index')),
      );
    }

    IconButton moveDownButton(int index) {
      return tester.widget<IconButton>(
        find.byKey(ValueKey<String>('lesson_document_media_move_down_$index')),
      );
    }

    expect(_blockTypes(document), ['paragraph', 'media', 'paragraph']);
    expect(moveUpButton(1).onPressed, isNotNull);
    expect(moveDownButton(1).onPressed, isNotNull);
    expect(moveUpButton(1).tooltip, 'Flytta media upp');
    expect(moveDownButton(1).tooltip, 'Flytta media ned');
    expect(moveUpButton(1).tooltip, isNot(contains('image')));
    expect(moveDownButton(1).tooltip, isNot(contains('77777777')));

    await tester.tap(
      find.byKey(const ValueKey<String>('lesson_document_media_move_up_1')),
    );
    await tester.pump();

    expect(_blockTypes(document), ['media', 'paragraph', 'paragraph']);
    final movedToTop = document.blocks[0] as LessonMediaBlock;
    expect(movedToTop.mediaType, 'image');
    expect(movedToTop.lessonMediaId, '77777777-7777-4777-8777-777777777777');
    expect(moveUpButton(0).onPressed, isNull);
    expect(moveDownButton(0).onPressed, isNotNull);
    expect(insertionIndex, 1);

    await tester.tap(
      find.byKey(const ValueKey<String>('lesson_document_media_move_down_0')),
    );
    await tester.pump();

    expect(_blockTypes(document), ['paragraph', 'media', 'paragraph']);
    final restored = document.blocks[1] as LessonMediaBlock;
    expect(restored.mediaType, 'image');
    expect(restored.lessonMediaId, '77777777-7777-4777-8777-777777777777');
    expect(insertionIndex, 2);

    await tester.tap(
      find.byKey(const ValueKey<String>('lesson_document_media_move_down_1')),
    );
    await tester.pump();

    expect(_blockTypes(document), ['paragraph', 'paragraph', 'media']);
    expect(moveUpButton(2).onPressed, isNotNull);
    expect(moveDownButton(2).onPressed, isNull);
    final preview = tester.widget<LessonDocumentPreview>(
      find.byKey(const ValueKey<String>('moved_media_preview')),
    );
    expect(preview.document.toJson(), document.toJson());
  });

  testWidgets('document editor media blocks hide internal metadata', (
    tester,
  ) async {
    const document = LessonDocument(
      blocks: [
        LessonMediaBlock(
          mediaType: 'image',
          lessonMediaId: '88888888-8888-4888-8888-888888888888',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 360,
            child: LessonDocumentEditor(
              document: document,
              media: const [
                LessonDocumentPreviewMedia(
                  lessonMediaId: '88888888-8888-4888-8888-888888888888',
                  mediaType: 'image',
                  state: 'ready',
                  label: 'cover.png',
                ),
              ],
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('cover.png'), findsOneWidget);
    expect(find.text('image'), findsOneWidget);
    expect(find.textContaining('Infogad media'), findsNothing);
    expect(find.textContaining('Flytta blocket'), findsNothing);
    expect(
      find.textContaining('88888888-8888-4888-8888-888888888888'),
      findsNothing,
    );
    expect(find.textContaining('Media: image'), findsNothing);
    expect(find.textContaining('media_type'), findsNothing);
    expect(find.textContaining('lesson_media_id'), findsNothing);
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

List<String> _blockTypes(LessonDocument document) {
  return document.blocks.map((block) => block.type).toList(growable: false);
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
