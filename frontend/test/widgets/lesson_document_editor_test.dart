import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/editor/document/lesson_document.dart';
import 'package:aveli/editor/document/lesson_document_editor.dart';
import 'package:aveli/editor/document/lesson_document_renderer.dart';
import 'package:aveli/shared/media/AveliLessonMediaPlayer.dart';

import '../helpers/lesson_document_fixture_corpus.dart';

double _renderedFontSize(WidgetTester tester, String text) {
  final richText = tester.widget<RichText>(
    find.text(text, findRichText: true).first,
  );
  return richText.text.style?.fontSize ?? 0;
}

double _renderedLineHeightPx(WidgetTester tester, String text) {
  final richText = tester.widget<RichText>(
    find.text(text, findRichText: true).first,
  );
  final fontSize =
      richText.text.style?.fontSize ?? richText.strutStyle?.fontSize ?? 0;
  final height =
      richText.text.style?.height ?? richText.strutStyle?.height ?? 1;
  return fontSize * height;
}

double _textFieldFontSize(WidgetTester tester, String fieldKey) {
  final textField = tester.widget<TextField>(
    find.byKey(ValueKey<String>(fieldKey)),
  );
  return textField.style?.fontSize ?? 0;
}

double _baselineY(WidgetTester tester, String text) {
  final finder = find.text(text, findRichText: true).first;
  final renderParagraph = tester.renderObject(finder) as dynamic;
  final top = tester.getTopLeft(finder).dy;
  return top +
      ((renderParagraph.computeDistanceToActualBaseline(TextBaseline.alphabetic)
              as double?) ??
          0);
}

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
    expect(find.text('Infogad media'), findsNothing);
    expect(find.text('Sparad media'), findsNothing);
    expect(
      find.textContaining(corpus.mediaRows.first.lessonMediaId),
      findsNothing,
    );
    expect(
      find.textContaining(corpus.mediaRows.first.mediaAssetId),
      findsNothing,
    );
    expect(find.text('Media: image'), findsNothing);
    expect(find.textContaining('Corpus image'), findsNothing);
    expect(find.textContaining('Status: ready'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
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

  testWidgets(
    'paper preview uses shared glass metrics plus four and row-aligned spacing',
    (tester) async {
      const document = LessonDocument(
        blocks: [
          LessonParagraphBlock(
            children: [LessonTextRun('First locked paragraph')],
          ),
          LessonParagraphBlock(
            children: [LessonTextRun('Second locked paragraph')],
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LessonDocumentPreview(document: document)),
        ),
      );
      final glassFontSize = _renderedFontSize(tester, 'First locked paragraph');
      final glassLineHeight = _renderedLineHeightPx(
        tester,
        'First locked paragraph',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LessonDocumentPreview(
              document: document,
              readingMode: LessonDocumentReadingMode.paper,
            ),
          ),
        ),
      );
      await tester.pump();

      final paperRichText = tester.widget<RichText>(
        find.text('First locked paragraph', findRichText: true).first,
      );
      final strutStyle = paperRichText.strutStyle;
      expect(
        paperRichText.text.style?.fontSize,
        closeTo(glassFontSize + 4, 0.001),
      );
      expect(strutStyle?.forceStrutHeight, isTrue);
      expect(
        _renderedLineHeightPx(tester, 'First locked paragraph'),
        closeTo(glassLineHeight + 4, 0.001),
      );
      expect(
        (strutStyle?.fontSize ?? 0) * (strutStyle?.height ?? 0),
        closeTo(glassLineHeight + 4, 0.001),
      );
      expect(
        _baselineY(tester, 'Second locked paragraph') -
            _baselineY(tester, 'First locked paragraph'),
        closeTo((glassLineHeight + 4) * 2, 0.05),
      );
    },
  );

  testWidgets(
    'paper preview keeps mixed inline formatting on full-line increments',
    (tester) async {
      const document = LessonDocument(
        blocks: [
          LessonParagraphBlock(
            children: [
              LessonTextRun('Bold', marks: [LessonInlineMark.bold]),
              LessonTextRun(' italic', marks: [LessonInlineMark.italic]),
              LessonTextRun(
                ' linked',
                marks: [LessonLinkMark('https://example.com')],
              ),
              LessonTextRun(
                ' underlined text that wraps onto another line in paper mode.',
                marks: [LessonInlineMark.underline],
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 220,
              child: LessonDocumentPreview(
                document: document,
                readingMode: LessonDocumentReadingMode.paper,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final richText = tester.widget<RichText>(
        find.textContaining('Bold', findRichText: true).first,
      );
      final box = tester.renderObject<RenderBox>(
        find.textContaining('Bold', findRichText: true).first,
      );
      final lineHeight =
          (richText.strutStyle?.fontSize ?? 0) *
          (richText.strutStyle?.height ?? 0);
      final lines = box.size.height / lineHeight;

      expect(richText.strutStyle?.forceStrutHeight, isTrue);
      expect(lines, closeTo(lines.roundToDouble(), 0.01));
    },
  );

  testWidgets(
    'paper preview snaps mixed heading and paragraph blocks to paper rows',
    (tester) async {
      const document = LessonDocument(
        blocks: [
          LessonHeadingBlock(
            level: 2,
            children: [LessonTextRun('Paper row heading')],
          ),
          LessonParagraphBlock(
            children: [
              LessonTextRun(
                'This paragraph wraps onto another line in paper mode and must keep the next block aligned to the shared paper rows.',
              ),
            ],
          ),
          LessonParagraphBlock(
            children: [LessonTextRun('Paper row follow-up')],
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              child: LessonDocumentPreview(
                document: document,
                readingMode: LessonDocumentReadingMode.paper,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final surface = find.byKey(
        const ValueKey<String>('lesson_document_paper_reading_surface'),
      );
      final metrics = LessonDocumentPaperMetrics.resolve(
        tester.element(surface),
      );
      final originY =
          tester.getTopLeft(surface).dy + metrics.contentPadding.top;
      final headingTop =
          tester
              .getTopLeft(
                find.text('Paper row heading', findRichText: true).first,
              )
              .dy -
          originY;
      final paragraphTop =
          tester
              .getTopLeft(
                find
                    .textContaining('This paragraph wraps', findRichText: true)
                    .first,
              )
              .dy -
          originY;
      final followUpTop =
          tester
              .getTopLeft(
                find.text('Paper row follow-up', findRichText: true).first,
              )
              .dy -
          originY;

      expect(headingTop, closeTo(0, 0.05));
      expect(
        paragraphTop / metrics.rowHeight,
        closeTo((paragraphTop / metrics.rowHeight).roundToDouble(), 0.05),
      );
      expect(
        followUpTop / metrics.rowHeight,
        closeTo((followUpTop / metrics.rowHeight).roundToDouble(), 0.05),
      );
      expect(
        (followUpTop - paragraphTop) / metrics.rowHeight,
        closeTo(
          ((followUpTop - paragraphTop) / metrics.rowHeight).roundToDouble(),
          0.05,
        ),
      );
    },
  );

  testWidgets('document preview fallback renders only image media', (
    tester,
  ) async {
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
                label: 'cover-photo.webp',
                resolvedUrl: 'https://cdn.test/image.webp',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Infogad media'), findsNothing);
    expect(find.text('Sparad media'), findsNothing);
    expect(find.textContaining('cover-photo.webp'), findsNothing);
    expect(find.textContaining(lessonMediaId), findsNothing);
    expect(find.textContaining('Media: image'), findsNothing);
    expect(find.textContaining('Status: ready'), findsNothing);
    expect(find.textContaining('media_type'), findsNothing);

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, double.infinity);
    expect(image.height, isNull);
    expect(image.fit, BoxFit.contain);
  });

  testWidgets('document preview fallback renders shared audio lesson player', (
    tester,
  ) async {
    const lessonMediaId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const audioUrl = 'https://cdn.test/audio.mp3';
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

    expect(find.text('Infogad media'), findsNothing);
    expect(find.text('Sparad media'), findsNothing);
    expect(find.textContaining('narration.mp3'), findsNothing);
    expect(find.textContaining(lessonMediaId), findsNothing);
    expect(find.textContaining('Media: audio'), findsNothing);
    expect(
      find.byWidgetPredicate((widget) {
        return widget is AveliLessonMediaPlayer &&
            widget.kind == 'audio' &&
            widget.mediaUrl == audioUrl &&
            widget.title == 'Lektionsljud' &&
            widget.preferLessonLayout;
      }),
      findsOneWidget,
    );
  });

  testWidgets(
    'document preview fallback renders video player without metadata',
    (tester) async {
      const lessonMediaId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      const videoUrl = 'https://cdn.test/video.mp4';
      const document = LessonDocument(
        blocks: [
          LessonMediaBlock(mediaType: 'video', lessonMediaId: lessonMediaId),
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
                  mediaType: 'video',
                  state: 'ready',
                  label: 'trailer.mp4',
                  resolvedUrl: videoUrl,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Infogad media'), findsNothing);
      expect(find.text('Sparad media'), findsNothing);
      expect(find.textContaining('trailer.mp4'), findsNothing);
      expect(find.textContaining(lessonMediaId), findsNothing);
      expect(find.textContaining('Media: video'), findsNothing);
      expect(
        find.byWidgetPredicate((widget) {
          return widget is AveliLessonMediaPlayer &&
              widget.kind == 'video' &&
              widget.mediaUrl == videoUrl &&
              widget.title == 'Lektionsvideo' &&
              widget.preferLessonLayout;
        }),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is AveliLessonMediaPlayer && widget.kind == 'audio',
        ),
        findsNothing,
      );
    },
  );

  testWidgets('document preview fallback renders shared document card', (
    tester,
  ) async {
    const lessonMediaId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
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

    expect(find.text('Infogad media'), findsNothing);
    expect(find.text('Sparad media'), findsNothing);
    expect(find.textContaining('handout.pdf'), findsNothing);
    expect(find.textContaining(lessonMediaId), findsNothing);
    expect(find.textContaining('Media: document'), findsNothing);
    expect(find.text('Lektionsfil'), findsOneWidget);
    expect(find.text('Ladda ner dokument'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(AveliLessonMediaPlayer), findsNothing);
  });

  testWidgets(
    'document editor scales heading fields by 1.6x without changing paragraphs',
    (tester) async {
      const document = LessonDocument(
        blocks: [
          LessonParagraphBlock(children: [LessonTextRun('Paragraph body')]),
          LessonHeadingBlock(
            level: 1,
            children: [LessonTextRun('Heading one')],
          ),
          LessonHeadingBlock(
            level: 2,
            children: [LessonTextRun('Heading two')],
          ),
          LessonHeadingBlock(
            level: 3,
            children: [LessonTextRun('Heading three')],
          ),
          LessonHeadingBlock(
            level: 4,
            children: [LessonTextRun('Heading four')],
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 520,
              child: LessonDocumentEditor(document: document, onChanged: _noop),
            ),
          ),
        ),
      );

      final theme = Theme.of(tester.element(find.byType(LessonDocumentEditor)));
      expect(
        _textFieldFontSize(tester, 'lesson_document_editor_node_0'),
        closeTo(theme.textTheme.bodyLarge?.fontSize ?? 0, 0.001),
      );
      expect(
        _textFieldFontSize(tester, 'lesson_document_editor_node_1'),
        closeTo((theme.textTheme.headlineMedium?.fontSize ?? 24) * 1.6, 0.001),
      );
      expect(
        _textFieldFontSize(tester, 'lesson_document_editor_node_2'),
        closeTo((theme.textTheme.headlineSmall?.fontSize ?? 24) * 1.6, 0.001),
      );
      expect(
        _textFieldFontSize(tester, 'lesson_document_editor_node_3'),
        closeTo((theme.textTheme.titleLarge?.fontSize ?? 20) * 1.6, 0.001),
      );
      expect(
        _textFieldFontSize(tester, 'lesson_document_editor_node_4'),
        closeTo((theme.textTheme.titleMedium?.fontSize ?? 20) * 1.6, 0.001),
      );
    },
  );

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

    const fieldKey = ValueKey('lesson_document_editor_node_0');
    await _selectTextRange(
      tester,
      const ValueKey('lesson_document_editor_node_0'),
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
  });

  testWidgets('document editor applies heading only to selected range', (
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

    const fieldKey = ValueKey('lesson_document_editor_node_0');
    await _selectTextRange(
      tester,
      fieldKey,
      text: 'Alpha Beta Gamma',
      start: 6,
      end: 10,
    );
    await _tapToolbar(tester, const Key('lesson_document_toolbar_heading'));

    expect(_blockTypes(document), ['paragraph', 'heading', 'paragraph']);
    expect(
      (document.blocks[0] as LessonParagraphBlock).children.single.text,
      'Alpha ',
    );
    expect(
      (document.blocks[1] as LessonHeadingBlock).children.single.text,
      'Beta',
    );
    expect(
      (document.blocks[2] as LessonParagraphBlock).children.single.text,
      ' Gamma',
    );
    expect(
      LessonDocument.fromJson(document.toJson()).toCanonicalJsonString(),
      document.toCanonicalJsonString(),
    );
  });

  testWidgets('document editor heading ignores out-of-range selections', (
    tester,
  ) async {
    final controller = LessonDocumentEditorController();
    const initial = LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Alpha Beta Gamma')]),
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
                  controller: controller,
                  onChanged: (next) => setState(() => document = next),
                ),
              );
            },
          ),
        ),
      ),
    );

    await _focusTextField(
      tester,
      const ValueKey('lesson_document_editor_node_0'),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    _forceControllerSelection(
      tester,
      const ValueKey('lesson_document_editor_node_0'),
      const TextSelection(baseOffset: 0, extentOffset: 99),
    );
    await tester.pump();
    await _tapToolbar(tester, const Key('lesson_document_toolbar_heading'));

    expect(document.toJson(), initial.toJson());
    expect(
      controller.lastCommandResult?.failure,
      LessonEditorCommandFailure.invalidRange,
    );
  });

  testWidgets('document editor applies heading to a full-block selection', (
    tester,
  ) async {
    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Full block')]),
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
      const ValueKey('lesson_document_editor_node_0'),
      text: 'Full block',
      start: 0,
      end: 10,
    );
    await _tapToolbar(tester, const Key('lesson_document_toolbar_heading'));

    expect(_blockTypes(document), ['heading']);
    final heading = document.blocks.single as LessonHeadingBlock;
    expect(heading.level, 2);
    expect(heading.children.single.text, 'Full block');
    expect(
      LessonDocument.fromJson(document.toJson()).toCanonicalJsonString(),
      document.toCanonicalJsonString(),
    );
  });

  testWidgets('document editor heading is a no-op for collapsed cursor', (
    tester,
  ) async {
    final controller = LessonDocumentEditorController();
    const initial = LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Alpha Beta Gamma')]),
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
                  controller: controller,
                  onChanged: (next) => setState(() => document = next),
                ),
              );
            },
          ),
        ),
      ),
    );

    const fieldKey = ValueKey('lesson_document_editor_node_0');
    await _selectTextRange(
      tester,
      fieldKey,
      text: 'Alpha Beta Gamma',
      start: 6,
      end: 6,
    );
    await _tapToolbar(tester, const Key('lesson_document_toolbar_heading'));

    expect(document.toJson(), initial.toJson());
    expect(
      controller.lastCommandResult?.failure,
      LessonEditorCommandFailure.collapsedSelection,
    );
  });

  testWidgets('document editor heading reports invalid selections', (
    tester,
  ) async {
    final controller = LessonDocumentEditorController();
    const initial = LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Alpha Beta Gamma')]),
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
                  controller: controller,
                  onChanged: (next) => setState(() => document = next),
                ),
              );
            },
          ),
        ),
      ),
    );

    await _tapToolbar(tester, const Key('lesson_document_toolbar_heading'));

    expect(document.toJson(), initial.toJson());
    expect(
      controller.lastCommandResult?.failure,
      LessonEditorCommandFailure.invalidSelection,
    );
  });

  testWidgets('document editor heading ignores stale invalid selections', (
    tester,
  ) async {
    final controller = LessonDocumentEditorController();
    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Alpha Beta Gamma')]),
      ],
    );
    const resetDocument = LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Short')]),
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
                  controller: controller,
                  lessonId: 'lesson-stale-selection',
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
      const ValueKey('lesson_document_editor_node_0'),
      text: 'Alpha Beta Gamma',
      start: 0,
      end: 16,
    );
    controller.resetTo(document: resetDocument, lessonId: 'lesson-reset');
    await tester.pump();
    await _tapToolbar(tester, const Key('lesson_document_toolbar_heading'));

    expect(controller.currentDocument?.toJson(), resetDocument.toJson());
    expect(
      controller.lastCommandResult?.failure,
      LessonEditorCommandFailure.textMismatch,
    );
  });

  testWidgets(
    'document editor heading reports controller document text mismatch',
    (tester) async {
      final controller = LessonDocumentEditorController();
      const initial = LessonDocument(
        blocks: [
          LessonParagraphBlock(children: [LessonTextRun('Alpha Beta Gamma')]),
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
                    controller: controller,
                    onChanged: (next) => setState(() => document = next),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await _focusTextField(
        tester,
        const ValueKey('lesson_document_editor_node_0'),
      );
      _forceControllerValue(
        tester,
        const ValueKey('lesson_document_editor_node_0'),
        const TextEditingValue(
          text: 'Controller drift',
          selection: TextSelection(baseOffset: 0, extentOffset: 10),
        ),
      );
      await tester.pump();
      await _tapToolbar(tester, const Key('lesson_document_toolbar_heading'));

      expect(document.toJson(), initial.toJson());
      expect(
        controller.lastCommandResult?.failure,
        LessonEditorCommandFailure.textMismatch,
      );
    },
  );

  testWidgets('document editor ignores inline formatting without selection', (
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
      find.byKey(const ValueKey('lesson_document_editor_node_0')),
    );
    await tester.pump();
    await _tapToolbar(tester, const Key('lesson_document_toolbar_bold'));

    expect(document.toJson(), initial.toJson());
  });

  testWidgets(
    'document editor heading extracts the active list item without disturbing siblings',
    (tester) async {
      var document = const LessonDocument(
        blocks: [
          LessonListBlock.bullet(
            items: [
              LessonListItem(children: [LessonTextRun('Alpha')]),
              LessonListItem(children: [LessonTextRun('Beta')]),
              LessonListItem(children: [LessonTextRun('Gamma')]),
            ],
          ),
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
        const ValueKey('lesson_document_editor_node_2'),
        text: 'Beta',
        start: 0,
        end: 4,
      );
      await _tapToolbar(tester, const Key('lesson_document_toolbar_heading'));

      expect(_blockTypes(document), ['bullet_list', 'heading', 'bullet_list']);
      expect(
        ((document.blocks[0] as LessonListBlock).items.single.children.single)
            .text,
        'Alpha',
      );
      expect(
        (document.blocks[1] as LessonHeadingBlock).children.single.text,
        'Beta',
      );
      expect(
        ((document.blocks[2] as LessonListBlock).items.single.children.single)
            .text,
        'Gamma',
      );
      expect(
        LessonDocument.fromJson(document.toJson()).toCanonicalJsonString(),
        document.toCanonicalJsonString(),
      );
    },
  );

  testWidgets(
    'document editor heading reports ordered-list selections as deferred',
    (tester) async {
      final controller = LessonDocumentEditorController();
      const initial = LessonDocument(
        blocks: [
          LessonListBlock.ordered(
            items: [
              LessonListItem(children: [LessonTextRun('One')]),
              LessonListItem(children: [LessonTextRun('Two')]),
            ],
          ),
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
                    controller: controller,
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
        const ValueKey('lesson_document_editor_node_1'),
        text: 'One',
        start: 0,
        end: 3,
      );
      await _tapToolbar(tester, const Key('lesson_document_toolbar_heading'));

      expect(document.toJson(), initial.toJson());
      expect(
        controller.lastCommandResult?.failure,
        LessonEditorCommandFailure.orderedListDeferred,
      );
    },
  );

  testWidgets('document editor heading reports unsupported targets', (
    tester,
  ) async {
    final controller = LessonDocumentEditorController();
    const initial = LessonDocument(
      blocks: [
        LessonMediaBlock(mediaType: 'image', lessonMediaId: 'lesson-media-1'),
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
                  controller: controller,
                  onChanged: (next) => setState(() => document = next),
                ),
              );
            },
          ),
        ),
      ),
    );

    await _tapToolbar(tester, const Key('lesson_document_toolbar_heading'));

    expect(document.toJson(), initial.toJson());
    expect(
      controller.lastCommandResult?.failure,
      LessonEditorCommandFailure.unsupportedTarget,
    );
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
      const ValueKey('lesson_document_editor_node_0'),
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

  testWidgets(
    'document editor preserves inline formatting through typing, scroll, and focus changes',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      var document = LessonDocument(
        blocks: List<LessonBlock>.unmodifiable([
          for (var index = 0; index < 14; index += 1)
            if (index == 8)
              const LessonParagraphBlock(
                children: [
                  LessonTextRun('Bold', marks: [LessonInlineMark.bold]),
                  LessonTextRun(' tail'),
                ],
              )
            else
              LessonParagraphBlock(
                children: [LessonTextRun('Filler paragraph $index')],
              ),
        ]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SizedBox(
                  height: 420,
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

      const targetKey = ValueKey<String>('lesson_document_editor_node_8');
      await _expectEditorKeyVisible(tester, targetKey);
      await tester.tap(find.byKey(targetKey));
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'BolXd tail',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      await tester.pump();

      var paragraph = document.blocks[8] as LessonParagraphBlock;
      expect(paragraph.children.map((run) => run.text).toList(), [
        'BolXd',
        ' tail',
      ]);
      expect(paragraph.children.first.marks.map((mark) => mark.type), ['bold']);
      expect(paragraph.children.last.marks, isEmpty);

      var segments = _editorTextSegments(tester, targetKey);
      expect(segments.map((segment) => segment.text).toList(), [
        'BolXd',
        ' tail',
      ]);
      expect(segments.first.style.fontWeight, FontWeight.w700);
      expect(segments.last.style.fontWeight, isNot(FontWeight.w700));

      await _expectEditorKeyVisible(
        tester,
        const ValueKey<String>('lesson_document_editor_node_13'),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('lesson_document_editor_node_13')),
        warnIfMissed: false,
      );
      await tester.pump();
      await _expectEditorKeyVisible(tester, targetKey);

      segments = _editorTextSegments(tester, targetKey);
      expect(segments.map((segment) => segment.text).toList(), [
        'BolXd',
        ' tail',
      ]);
      expect(segments.first.style.fontWeight, FontWeight.w700);
      expect(segments.last.style.fontWeight, isNot(FontWeight.w700));
    },
  );

  testWidgets(
    'document editor preserves mixed inline formatting across save and reload',
    (tester) async {
      var document = const LessonDocument(
        blocks: [
          LessonParagraphBlock(
            children: [
              LessonTextRun('Bold', marks: [LessonInlineMark.bold]),
              LessonTextRun(' and '),
              LessonTextRun('Italic', marks: [LessonInlineMark.italic]),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SizedBox(
                  height: 420,
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

      const fieldKey = ValueKey<String>('lesson_document_editor_node_0');
      await tester.tap(find.byKey(fieldKey));
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'BoXld and Italic',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pump();

      final savedPayload = document.toJson();
      final reloaded = LessonDocument.fromJson(savedPayload);

      _expectRunTextsAndMarks(
        (reloaded.blocks.single as LessonParagraphBlock).children,
        const ['BoXld', ' and ', 'Italic'],
        const [
          ['bold'],
          <String>[],
          ['italic'],
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 420,
              child: LessonDocumentEditor(
                document: reloaded,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final segments = _editorTextSegments(tester, fieldKey);
      expect(segments.map((segment) => segment.text).toList(), [
        'BoXld',
        ' and ',
        'Italic',
      ]);
      expect(segments[0].style.fontWeight, FontWeight.w700);
      expect(segments[1].style.fontWeight, isNot(FontWeight.w700));
      expect(segments[2].style.fontStyle, FontStyle.italic);
    },
  );

  testWidgets(
    'document editor preserves bold and italic marks through delete edits',
    (tester) async {
      var document = const LessonDocument(
        blocks: [
          LessonParagraphBlock(
            children: [
              LessonTextRun('Bold', marks: [LessonInlineMark.bold]),
              LessonTextRun(' and '),
              LessonTextRun('Italic', marks: [LessonInlineMark.italic]),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SizedBox(
                  height: 420,
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

      const fieldKey = ValueKey<String>('lesson_document_editor_node_0');
      await tester.tap(find.byKey(fieldKey));
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Bod and Italic',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();

      var paragraph = document.blocks.single as LessonParagraphBlock;
      _expectRunTextsAndMarks(
        paragraph.children,
        const ['Bod', ' and ', 'Italic'],
        const [
          ['bold'],
          <String>[],
          ['italic'],
        ],
      );

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Bod and Italc',
          selection: TextSelection.collapsed(offset: 12),
        ),
      );
      await tester.pump();

      paragraph = document.blocks.single as LessonParagraphBlock;
      _expectRunTextsAndMarks(
        paragraph.children,
        const ['Bod', ' and ', 'Italc'],
        const [
          ['bold'],
          <String>[],
          ['italic'],
        ],
      );
    },
  );

  testWidgets('document editor bold button toggles selection on and off', (
    tester,
  ) async {
    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Toggle me')]),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                height: 420,
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

    const fieldKey = ValueKey<String>('lesson_document_editor_node_0');
    await _selectTextRange(
      tester,
      fieldKey,
      text: 'Toggle me',
      start: 0,
      end: 6,
    );
    await _tapToolbar(tester, const Key('lesson_document_toolbar_bold'));

    var paragraph = document.blocks.single as LessonParagraphBlock;
    expect(paragraph.children.first.text, 'Toggle');
    expect(paragraph.children.first.marks.map((mark) => mark.type), ['bold']);

    await _selectTextRange(
      tester,
      fieldKey,
      text: 'Toggle me',
      start: 0,
      end: 6,
    );
    await _tapToolbar(tester, const Key('lesson_document_toolbar_bold'));

    paragraph = document.blocks.single as LessonParagraphBlock;
    expect(paragraph.children.single.text, 'Toggle me');
    expect(paragraph.children.single.marks, isEmpty);
  });

  testWidgets('document editor inserts media at document top', (tester) async {
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
    final controller = LessonDocumentEditorController();
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
                      controller: controller,
                      onChanged: (next) => setState(() => document = next),
                      onInsertionIndexChanged: (index) {
                        insertionIndex = index;
                      },
                    ),
                  ),
                  ElevatedButton(
                    key: const Key('insert_image_at_editor_position'),
                    onPressed: () => controller.insertMediaBlock(
                      mediaType: 'image',
                      lessonMediaId: '55555555-5555-4555-8555-555555555555',
                    ),
                    child: const Text('Insert image'),
                  ),
                  ElevatedButton(
                    key: const Key('insert_audio_at_editor_position'),
                    onPressed: () => controller.insertMediaBlock(
                      mediaType: 'audio',
                      lessonMediaId: '66666666-6666-4666-8666-666666666666',
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
      const ValueKey('lesson_document_editor_node_0'),
      text: 'Intro',
      start: 0,
      end: 5,
    );
    await tester.tap(find.byKey(const Key('insert_image_at_editor_position')));
    await tester.pump();

    expect(_blockTypes(document), ['media', 'paragraph', 'paragraph']);
    expect(insertionIndex, 1);
    expect(
      (document.blocks[1] as LessonParagraphBlock).children.single.text,
      'Intro',
    );
    expect(
      (document.blocks[2] as LessonParagraphBlock).children.single.text,
      'Outro',
    );
    final imageBlock = document.blocks[0] as LessonMediaBlock;
    expect(imageBlock.mediaType, 'image');
    expect(imageBlock.lessonMediaId, '55555555-5555-4555-8555-555555555555');
    final preview = tester.widget<LessonDocumentPreview>(
      find.byKey(const ValueKey<String>('positioned_media_preview')),
    );
    expect(preview.document.toJson(), document.toJson());

    await tester.tap(
      find.byKey(const ValueKey('lesson_document_editor_node_1')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('insert_audio_at_editor_position')));
    await tester.pump();

    expect(_blockTypes(document), ['media', 'media', 'paragraph', 'paragraph']);
    expect(insertionIndex, 1);
    expect(
      (document.blocks[3] as LessonParagraphBlock).children.single.text,
      'Outro',
    );
    final audioBlock = document.blocks[0] as LessonMediaBlock;
    expect(audioBlock.mediaType, 'audio');
    expect(audioBlock.lessonMediaId, '66666666-6666-4666-8666-666666666666');
    final retainedImageBlock = document.blocks[1] as LessonMediaBlock;
    expect(retainedImageBlock.mediaType, 'image');
    expect(
      retainedImageBlock.lessonMediaId,
      '55555555-5555-4555-8555-555555555555',
    );
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

    IconButton moveUpButton() {
      return tester.widget<IconButton>(
        find.byKey(
          const ValueKey<String>('lesson_document_media_move_up_node_1'),
        ),
      );
    }

    IconButton moveDownButton() {
      return tester.widget<IconButton>(
        find.byKey(
          const ValueKey<String>('lesson_document_media_move_down_node_1'),
        ),
      );
    }

    expect(_blockTypes(document), ['paragraph', 'media', 'paragraph']);
    expect(moveUpButton().onPressed, isNotNull);
    expect(moveDownButton().onPressed, isNotNull);
    expect(moveUpButton().tooltip, 'Flytta media upp');
    expect(moveDownButton().tooltip, 'Flytta media ned');
    expect(moveUpButton().tooltip, isNot(contains('image')));
    expect(moveDownButton().tooltip, isNot(contains('77777777')));

    await tester.tap(
      find.byKey(
        const ValueKey<String>('lesson_document_media_move_up_node_1'),
      ),
    );
    await tester.pump();

    expect(_blockTypes(document), ['media', 'paragraph', 'paragraph']);
    final movedToTop = document.blocks[0] as LessonMediaBlock;
    expect(movedToTop.mediaType, 'image');
    expect(movedToTop.lessonMediaId, '77777777-7777-4777-8777-777777777777');
    expect(moveUpButton().onPressed, isNull);
    expect(moveDownButton().onPressed, isNotNull);
    expect(insertionIndex, 1);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('lesson_document_media_move_down_node_1'),
      ),
    );
    await tester.pump();

    expect(_blockTypes(document), ['paragraph', 'media', 'paragraph']);
    final restored = document.blocks[1] as LessonMediaBlock;
    expect(restored.mediaType, 'image');
    expect(restored.lessonMediaId, '77777777-7777-4777-8777-777777777777');
    expect(insertionIndex, 2);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('lesson_document_media_move_down_node_1'),
      ),
    );
    await tester.pump();

    expect(_blockTypes(document), ['paragraph', 'paragraph', 'media']);
    expect(moveUpButton().onPressed, isNotNull);
    expect(moveDownButton().onPressed, isNull);
    final preview = tester.widget<LessonDocumentPreview>(
      find.byKey(const ValueKey<String>('moved_media_preview')),
    );
    expect(preview.document.toJson(), document.toJson());
  });

  testWidgets('document editor moves paragraph heading and list blocks', (
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
        LessonParagraphBlock(children: [LessonTextRun('Paragraph')]),
        LessonHeadingBlock(level: 2, children: [LessonTextRun('Heading')]),
        LessonListBlock.bullet(
          items: [
            LessonListItem(children: [LessonTextRun('List item')]),
          ],
        ),
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

    IconButton textMoveUp(String nodeId) {
      return tester.widget<IconButton>(
        find.byKey(ValueKey<String>('lesson_document_text_move_up_$nodeId')),
      );
    }

    IconButton textMoveDown(String nodeId) {
      return tester.widget<IconButton>(
        find.byKey(ValueKey<String>('lesson_document_text_move_down_$nodeId')),
      );
    }

    expect(textMoveUp('node_0').onPressed, isNull);
    expect(textMoveDown('node_0').onPressed, isNotNull);
    expect(textMoveUp('node_1').onPressed, isNotNull);
    expect(textMoveDown('node_1').onPressed, isNotNull);
    expect(textMoveUp('node_2').onPressed, isNotNull);
    expect(textMoveDown('node_2').onPressed, isNull);
    expect(textMoveUp('node_1').tooltip, 'Flytta text upp');
    expect(textMoveDown('node_1').tooltip, 'Flytta text ned');

    await tester.tap(
      find.byKey(const ValueKey<String>('lesson_document_text_move_up_node_1')),
    );
    await tester.pump();

    expect(_blockTypes(document), ['heading', 'paragraph', 'bullet_list']);
    expect(
      (document.blocks[0] as LessonHeadingBlock).children.single.text,
      'Heading',
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('lesson_document_text_move_down_node_0'),
      ),
    );
    await tester.pump();

    expect(_blockTypes(document), ['heading', 'bullet_list', 'paragraph']);
    expect(
      ((document.blocks[1] as LessonListBlock).items.single.children.single)
          .text,
      'List item',
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('lesson_document_text_move_down_node_2'),
      ),
    );
    await tester.pump();

    expect(_blockTypes(document), ['heading', 'paragraph', 'bullet_list']);
    expect(
      (document.blocks[1] as LessonParagraphBlock).children.single.text,
      'Paragraph',
    );
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
      find.byKey(const ValueKey('lesson_document_editor_node_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('lesson_document_editor_node_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('lesson_document_editor_node_3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('lesson_document_editor_node_6')),
      findsOneWidget,
    );
    await _expectEditorKeyVisible(
      tester,
      const ValueKey('lesson_document_media_node_8'),
    );
    await _expectEditorKeyVisible(
      tester,
      const ValueKey('lesson_document_media_node_9'),
    );
    await _expectEditorKeyVisible(
      tester,
      const ValueKey('lesson_document_media_node_10'),
    );
    await _expectEditorKeyVisible(
      tester,
      const ValueKey('lesson_document_media_node_11'),
    );
    await _expectEditorKeyVisible(
      tester,
      const ValueKey('lesson_document_cta:node_12:label'),
    );
    await _expectEditorKeyVisible(
      tester,
      const ValueKey('lesson_document_cta:node_12:url'),
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
      const ValueKey('lesson_document_editor_node_0'),
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

  testWidgets('explicit delete-block command removes only the selected block', (
    tester,
  ) async {
    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('First')]),
        LessonParagraphBlock(children: [LessonTextRun('Second')]),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                height: 420,
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
      find.byKey(const ValueKey<String>('lesson_document_editor_node_0')),
    );
    await tester.pump();
    await _tapToolbar(
      tester,
      const Key('lesson_document_toolbar_delete_block'),
    );

    expect(document.blocks, hasLength(1));
    final paragraph = document.blocks.single as LessonParagraphBlock;
    expect(paragraph.children.single.text, 'Second');
  });

  testWidgets('node identity edits the same block after deleting above it', (
    tester,
  ) async {
    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('A')]),
        LessonParagraphBlock(children: [LessonTextRun('B')]),
        LessonParagraphBlock(children: [LessonTextRun('C')]),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                height: 420,
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
      find.byKey(const ValueKey<String>('lesson_document_editor_node_1')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('lesson_document_editor_node_0')),
    );
    await tester.pump();
    await _tapToolbar(
      tester,
      const Key('lesson_document_toolbar_delete_block'),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('lesson_document_editor_node_1')),
      'B edited',
    );
    await tester.pump();

    expect(_blockTypes(document), ['paragraph', 'paragraph']);
    expect(
      (document.blocks[0] as LessonParagraphBlock).children.single.text,
      'B edited',
    );
    expect(
      (document.blocks[1] as LessonParagraphBlock).children.single.text,
      'C',
    );
  });

  testWidgets('node identity edits the same block after inserting above it', (
    tester,
  ) async {
    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('A')]),
        LessonParagraphBlock(children: [LessonTextRun('B')]),
      ],
    );
    final controller = LessonDocumentEditorController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                height: 420,
                child: LessonDocumentEditor(
                  document: document,
                  controller: controller,
                  onChanged: (next) => setState(() => document = next),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('lesson_document_editor_node_0')),
    );
    await tester.pump();
    expect(
      controller.insertMediaBlock(
        mediaType: 'image',
        lessonMediaId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      ),
      isTrue,
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey<String>('lesson_document_editor_node_1')),
      'B edited',
    );
    await tester.pump();

    expect(_blockTypes(document), ['media', 'paragraph', 'paragraph']);
    expect(
      (document.blocks[2] as LessonParagraphBlock).children.single.text,
      'B edited',
    );
  });

  testWidgets('node identity edits the same block after reorder', (
    tester,
  ) async {
    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('A')]),
        LessonMediaBlock(
          mediaType: 'image',
          lessonMediaId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        ),
        LessonParagraphBlock(children: [LessonTextRun('B')]),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                height: 420,
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
      find.byKey(
        const ValueKey<String>('lesson_document_media_move_down_node_1'),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey<String>('lesson_document_editor_node_2')),
      'B edited',
    );
    await tester.pump();

    expect(_blockTypes(document), ['paragraph', 'paragraph', 'media']);
    expect(
      (document.blocks[1] as LessonParagraphBlock).children.single.text,
      'B edited',
    );
  });

  testWidgets('node identity edits the same list item after deleting above', (
    tester,
  ) async {
    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('A')]),
        LessonListBlock.bullet(
          items: [
            LessonListItem(children: [LessonTextRun('B')]),
            LessonListItem(children: [LessonTextRun('C')]),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                height: 420,
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
      find.byKey(const ValueKey<String>('lesson_document_editor_node_0')),
    );
    await tester.pump();
    await _tapToolbar(
      tester,
      const Key('lesson_document_toolbar_delete_block'),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('lesson_document_editor_node_3')),
      'C edited',
    );
    await tester.pump();

    expect(_blockTypes(document), ['bullet_list']);
    final list = document.blocks.single as LessonListBlock;
    expect(list.items[0].children.single.text, 'B');
    expect(list.items[1].children.single.text, 'C edited');
  });

  testWidgets('node identity edits CTA fields after deleting above', (
    tester,
  ) async {
    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('A')]),
        LessonCtaBlock(label: 'Book', targetUrl: '/book'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                height: 420,
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
      find.byKey(const ValueKey<String>('lesson_document_editor_node_0')),
    );
    await tester.pump();
    await _tapToolbar(
      tester,
      const Key('lesson_document_toolbar_delete_block'),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('lesson_document_cta:node_1:label')),
      'Join now',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('lesson_document_cta:node_1:url')),
      '/join',
    );
    await tester.pump();

    expect(_blockTypes(document), ['cta']);
    final cta = document.blocks.single as LessonCtaBlock;
    expect(cta.label, 'Join now');
    expect(cta.targetUrl, '/join');
  });

  testWidgets('backspace on an empty final block removes it', (tester) async {
    var document = const LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Only')]),
      ],
    );
    var changeCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                height: 420,
                child: LessonDocumentEditor(
                  document: document,
                  onChanged: (next) => setState(() {
                    document = next;
                    changeCount += 1;
                  }),
                ),
              );
            },
          ),
        ),
      ),
    );

    final finder = find.byKey(
      const ValueKey<String>('lesson_document_editor_node_0'),
    );
    await tester.tap(finder);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      ),
    );
    await tester.pump();

    expect(document.blocks, hasLength(1));
    expect(
      ((document.blocks.single as LessonParagraphBlock).children.single).text,
      '',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(document.blocks, isEmpty);
    final changesAfterDelete = changeCount;
    await tester.pump();
    expect(changeCount, changesAfterDelete);
  });

  testWidgets(
    'empty document affordance inserts first paragraph only on text',
    (tester) async {
      var document = LessonDocument.empty();
      var changeCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SizedBox(
                  height: 420,
                  child: LessonDocumentEditor(
                    document: document,
                    onChanged: (next) => setState(() {
                      document = next;
                      changeCount += 1;
                    }),
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(document.blocks, isEmpty);
      expect(changeCount, 0);
      await tester.pump();
      expect(changeCount, 0);

      await tester.enterText(
        find.byKey(const ValueKey<String>('lesson_document_editor_block_0')),
        'Hello',
      );
      await tester.pump();

      expect(document.blocks, hasLength(1));
      final paragraph = document.blocks.single as LessonParagraphBlock;
      expect(paragraph.children.single.text, 'Hello');
      expect(changeCount, 1);
    },
  );
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

Future<void> _focusTextField(WidgetTester tester, ValueKey<String> key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void _forceControllerSelection(
  WidgetTester tester,
  ValueKey<String> key,
  TextSelection selection,
) {
  final textField = tester.widget<TextField>(find.byKey(key));
  final controller = textField.controller!;
  controller.value = controller.value.copyWith(selection: selection);
}

void _forceControllerValue(
  WidgetTester tester,
  ValueKey<String> key,
  TextEditingValue value,
) {
  final textField = tester.widget<TextField>(find.byKey(key));
  textField.controller!.value = value;
}

Future<void> _tapToolbar(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _expectEditorKeyVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pump();
    expect(finder, findsOneWidget);
    return;
  }
  final editorScrollable = find
      .descendant(
        of: find.byType(LessonDocumentEditor),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  await _scrollEditorUntilVisible(tester, finder, editorScrollable, delta: 240);
  if (finder.evaluate().isEmpty) {
    await _scrollEditorUntilVisible(
      tester,
      finder,
      editorScrollable,
      delta: -240,
    );
  }
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pump();
  }
  expect(finder, findsOneWidget);
}

Future<void> _scrollEditorUntilVisible(
  WidgetTester tester,
  Finder finder,
  Finder scrollable, {
  required double delta,
}) async {
  try {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: scrollable,
      maxScrolls: 20,
    );
  } on StateError {
    // The target may be above the current lazy-list window; callers retry in
    // the opposite direction before asserting.
  }
}

List<_TextSegment> _editorTextSegments(
  WidgetTester tester,
  ValueKey<String> key,
) {
  final finder = find.byKey(key);
  final field = tester.widget<TextField>(finder);
  final text = field.controller!.buildTextSpan(
    context: tester.element(finder),
    style: field.style,
    withComposing: false,
  );
  return _flattenTextSpan(text);
}

List<_TextSegment> _flattenTextSpan(TextSpan span) {
  final output = <_TextSegment>[];
  final baseStyle = span.style ?? const TextStyle();

  void visit(TextSpan current, TextStyle inherited) {
    final style = inherited.merge(current.style);
    final text = current.text;
    if (text != null && text.isNotEmpty) {
      output.add(_TextSegment(text: text, style: style));
    }
    for (final child in current.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) {
        visit(child, style);
      }
    }
  }

  visit(span, baseStyle);
  return output;
}

class _TextSegment {
  const _TextSegment({required this.text, required this.style});

  final String text;
  final TextStyle style;
}

void _expectRunTextsAndMarks(
  List<LessonTextRun> runs,
  List<String> expectedTexts,
  List<List<String>> expectedMarks,
) {
  expect(runs.map((run) => run.text).toList(growable: false), expectedTexts);
  expect(
    runs
        .map(
          (run) => run.marks.map((mark) => mark.type).toList(growable: false),
        )
        .toList(growable: false),
    expectedMarks,
  );
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

void _noop(LessonDocument _) {}
