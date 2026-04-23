import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/editor/document/lesson_document.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/lesson_page.dart';
import 'package:aveli/shared/media/AveliLessonImage.dart';
import 'package:aveli/shared/media/AveliLessonMediaPlayer.dart';
import 'package:aveli/shared/utils/resolved_media_contract.dart';

import '../helpers/lesson_document_fixture_corpus.dart';

const _videoMediaId = '33333333-3333-4333-8333-333333333333';

class _StyledTextSegment {
  const _StyledTextSegment(this.text, this.style);

  final String text;
  final TextStyle? style;
}

void _collectStyledTextSegments(
  InlineSpan span,
  List<_StyledTextSegment> segments, {
  TextStyle? inheritedStyle,
}) {
  if (span is! TextSpan) return;
  final effectiveStyle = inheritedStyle?.merge(span.style) ?? span.style;
  final text = span.text;
  if (text != null && text.isNotEmpty) {
    segments.add(_StyledTextSegment(text, effectiveStyle));
  }
  final children = span.children;
  if (children == null || children.isEmpty) {
    return;
  }
  for (final child in children) {
    _collectStyledTextSegments(child, segments, inheritedStyle: effectiveStyle);
  }
}

Finder _lessonMediaPlayerFinder(String kind) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is AveliLessonMediaPlayer &&
        widget.kind.trim().toLowerCase() == kind,
    description: 'AveliLessonMediaPlayer(kind: $kind)',
  );
}

List<_StyledTextSegment> _rendererStyledTextSegments(WidgetTester tester) {
  final segments = <_StyledTextSegment>[];
  final richTextFinder = find.descendant(
    of: find.byType(LessonPageRenderer),
    matching: find.byType(RichText),
  );
  for (final richText in tester.widgetList<RichText>(richTextFinder)) {
    _collectStyledTextSegments(richText.text, segments);
  }
  return segments;
}

List<TextStyle?> _textStylesForText(WidgetTester tester, String target) {
  return [
    for (final segment in _rendererStyledTextSegments(tester))
      if (segment.text.contains(target)) segment.style,
  ];
}

List<LessonMediaItem> _lessonMediaItemsFromCorpus(
  LessonDocumentFixtureCorpus corpus,
) {
  return [
    for (final row in corpus.mediaRows)
      LessonMediaItem(
        id: row.lessonMediaId,
        lessonId: 'lesson-1',
        mediaAssetId: row.mediaAssetId,
        position: 1,
        mediaType: row.mediaType,
        state: row.state,
        media: ResolvedMediaData(
          mediaId: row.mediaAssetId,
          state: row.state,
          resolvedUrl: row.resolvedUrl,
        ),
      ),
  ];
}

Future<void> _pumpLearnerRenderer(
  WidgetTester tester, {
  required LessonDocument document,
  required List<LessonMediaItem> lessonMedia,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LessonPageRenderer(
            document: document,
            lessonMedia: lessonMedia,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'learner renderer uses document media and CTA nodes without markdown tokens',
    (tester) async {
      final corpus = loadLessonDocumentFixtureCorpus();
      final document = corpus.document('full_capability_document');

      await _pumpLearnerRenderer(
        tester,
        document: document,
        lessonMedia: _lessonMediaItemsFromCorpus(corpus),
      );
      await tester.pump();

      expect(find.byType(AveliLessonImage), findsOneWidget);
      expect(_lessonMediaPlayerFinder('audio'), findsOneWidget);
      expect(_lessonMediaPlayerFinder('video'), findsOneWidget);
      expect(find.text('Ladda ner dokument'), findsOneWidget);
      for (final row in corpus.mediaRows) {
        expect(
          find.textContaining(row.lessonMediaId, findRichText: true),
          findsNothing,
        );
        expect(
          find.textContaining(row.mediaAssetId, findRichText: true),
          findsNothing,
        );
      }
      expect(find.text('Book now'), findsOneWidget);
      expect(find.textContaining('!image(', findRichText: true), findsNothing);
      expect(
        find.textContaining('!document(', findRichText: true),
        findsNothing,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('learner renderer preserves inline marks, headings, and lists', (
    tester,
  ) async {
    final corpus = loadLessonDocumentFixtureCorpus();
    final document = corpus.document('full_capability_document');

    await _pumpLearnerRenderer(
      tester,
      document: document,
      lessonMedia: _lessonMediaItemsFromCorpus(corpus),
    );
    await tester.pump();

    final boldStyles = _textStylesForText(tester, 'Bold');
    final italicStyles = _textStylesForText(tester, 'Italic');
    final underlineStyles = _textStylesForText(tester, 'Underline');

    expect(find.text('2.'), findsOneWidget);
    expect(find.text('3.'), findsOneWidget);
    expect(
      boldStyles.any((style) => style?.fontWeight == FontWeight.w700),
      isTrue,
    );
    expect(
      italicStyles.any((style) => style?.fontStyle == FontStyle.italic),
      isTrue,
    );
    expect(
      underlineStyles.any(
        (style) =>
            style?.decoration?.contains(TextDecoration.underline) ?? false,
      ),
      isTrue,
    );
  });

  testWidgets(
    'learner renderer shows explicit error for unresolved document media',
    (tester) async {
      const document = LessonDocument(
        blocks: [
          LessonParagraphBlock(children: [LessonTextRun('Intro')]),
          LessonMediaBlock(mediaType: 'video', lessonMediaId: _videoMediaId),
        ],
      );

      await _pumpLearnerRenderer(
        tester,
        document: document,
        lessonMedia: const <LessonMediaItem>[],
      );
      await tester.pump();

      expect(find.text('Lektionsmedia kunde inte laddas.'), findsOneWidget);
      expect(find.textContaining(_videoMediaId), findsNothing);
      expect(find.textContaining('video'), findsNothing);
      expect(_lessonMediaPlayerFinder('video'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('learner renderer treats empty document as missing content', (
    tester,
  ) async {
    await _pumpLearnerRenderer(
      tester,
      document: LessonDocument.empty(),
      lessonMedia: const <LessonMediaItem>[],
    );
    await tester.pump();

    expect(find.text('Lektionsinnehållet saknas.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'learner content renderer toggles glass and paper reading modes',
    (tester) async {
      final corpus = loadLessonDocumentFixtureCorpus();
      final document = corpus.document('full_capability_document');
      final initialJson = document.toCanonicalJsonString();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LearnerLessonContentRenderer(
                document: document,
                lessonMedia: _lessonMediaItemsFromCorpus(corpus),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('lesson_document_reading_mode_toggle')),
        findsOneWidget,
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
      expect(tester.takeException(), isNull);
    },
  );
}
