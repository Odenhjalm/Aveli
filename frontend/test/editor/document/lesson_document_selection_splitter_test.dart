import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/editor/document/lesson_document.dart';
import 'package:aveli/editor/document/lesson_document_selection_splitter.dart';

void main() {
  test('splits a paragraph selection into paragraph heading paragraph', () {
    const document = LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Alpha Beta Gamma')]),
      ],
    );

    final result = splitLessonDocumentSelection(
      document: document,
      target: const LessonTextBlockSelectionTarget(blockIndex: 0),
      start: 6,
      end: 10,
      conversion: const LessonSelectionHeadingConversion(level: 2),
    );

    expect(result.status, LessonSelectionSplitStatus.applied);
    expect(_blockTypes(result.document), ['paragraph', 'heading', 'paragraph']);
    expect(
      (result.document.blocks[0] as LessonParagraphBlock).children.single.text,
      'Alpha ',
    );
    expect(
      (result.document.blocks[1] as LessonHeadingBlock).children.single.text,
      'Beta',
    );
    expect(
      (result.document.blocks[2] as LessonParagraphBlock).children.single.text,
      ' Gamma',
    );
    expect(result.metadata?.sourceBlockIndex, 0);
    expect(result.metadata?.sourceListItemIndex, isNull);
    expect(result.metadata?.replacementCount, 3);
    expect(result.metadata?.selectedReplacementIndex, 1);
    expect(
      result.metadata?.selectedOutputTargetType,
      LessonSelectionSplitOutputTargetType.blockText,
    );
    expect(
      result.metadata?.identityRemapHints[1].blockIdentityAction,
      LessonSelectionSplitIdentityAction.reuseSourceBlockRuntimeIdentity,
    );
    _expectRoundTrip(result);
  });

  test('converts a full text block selection into one heading', () {
    const document = LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Whole block')]),
      ],
    );

    final result = splitLessonDocumentSelection(
      document: document,
      target: const LessonTextBlockSelectionTarget(blockIndex: 0),
      start: 0,
      end: 11,
      conversion: const LessonSelectionHeadingConversion(level: 3),
    );

    expect(result.status, LessonSelectionSplitStatus.applied);
    expect(result.document.blocks, hasLength(1));
    final heading = result.document.blocks.single as LessonHeadingBlock;
    expect(heading.level, 3);
    expect(heading.children.single.text, 'Whole block');
    expect(result.metadata?.replacementCount, 1);
    expect(result.metadata?.selectedReplacementIndex, 0);
    expect(
      result.metadata?.identityRemapHints.single.blockIdentityAction,
      LessonSelectionSplitIdentityAction.reuseSourceBlockRuntimeIdentity,
    );
    _expectRoundTrip(result);
  });

  test('collapsed selections are rejected without document mutation', () {
    const document = LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Alpha Beta')]),
      ],
    );

    final result = splitLessonDocumentSelection(
      document: document,
      target: const LessonTextBlockSelectionTarget(blockIndex: 0),
      start: 5,
      end: 5,
      conversion: const LessonSelectionHeadingConversion(level: 2),
    );

    expect(result.status, LessonSelectionSplitStatus.collapsedSelection);
    expect(result.document, same(document));
    expect(result.metadata, isNull);
  });

  test('preserves inline marks across before selected and after fragments', () {
    const document = LessonDocument(
      blocks: [
        LessonParagraphBlock(
          children: [
            LessonTextRun('Alpha ', marks: [LessonInlineMark.bold]),
            LessonTextRun('Beta', marks: [LessonInlineMark.italic]),
            LessonTextRun(' Gamma', marks: [LessonInlineMark.underline]),
          ],
        ),
      ],
    );

    final result = splitLessonDocumentSelection(
      document: document,
      target: const LessonTextBlockSelectionTarget(blockIndex: 0),
      start: 6,
      end: 10,
      conversion: const LessonSelectionHeadingConversion(level: 2),
    );

    final before = result.document.blocks[0] as LessonParagraphBlock;
    final selected = result.document.blocks[1] as LessonHeadingBlock;
    final after = result.document.blocks[2] as LessonParagraphBlock;
    expect(before.children.single.marks.map((mark) => mark.type), ['bold']);
    expect(selected.children.single.marks.map((mark) => mark.type), ['italic']);
    expect(after.children.single.marks.map((mark) => mark.type), ['underline']);
    _expectRoundTrip(result);
  });

  test('optional block id metadata is not duplicated after split', () {
    const document = LessonDocument(
      blocks: [
        LessonParagraphBlock(
          id: 'source-block',
          children: [LessonTextRun('Alpha Beta Gamma')],
        ),
      ],
    );

    final result = splitLessonDocumentSelection(
      document: document,
      target: const LessonTextBlockSelectionTarget(blockIndex: 0),
      start: 6,
      end: 10,
      conversion: const LessonSelectionHeadingConversion(level: 2),
    );

    final ids = [
      for (final block in result.document.blocks)
        if (block.id != null) block.id,
    ];
    expect(ids, isEmpty);
    _expectRoundTrip(result);
  });

  test(
    'splits a bullet list item into before list converted block after list',
    () {
      const document = LessonDocument(
        blocks: [
          LessonListBlock.bullet(
            id: 'source-list',
            items: [
              LessonListItem(
                id: 'alpha-id',
                children: [LessonTextRun('Alpha')],
              ),
              LessonListItem(
                id: 'selected-id',
                children: [LessonTextRun('Before Beta After')],
              ),
              LessonListItem(
                id: 'gamma-id',
                children: [LessonTextRun('Gamma')],
              ),
            ],
          ),
        ],
      );

      final result = splitLessonDocumentSelection(
        document: document,
        target: const LessonListItemSelectionTarget(
          blockIndex: 0,
          itemIndex: 1,
        ),
        start: 7,
        end: 11,
        conversion: const LessonSelectionHeadingConversion(level: 2),
      );

      expect(result.status, LessonSelectionSplitStatus.applied);
      expect(_blockTypes(result.document), [
        'bullet_list',
        'heading',
        'bullet_list',
      ]);
      final beforeList = result.document.blocks[0] as LessonListBlock;
      final heading = result.document.blocks[1] as LessonHeadingBlock;
      final afterList = result.document.blocks[2] as LessonListBlock;
      expect(beforeList.id, isNull);
      expect(beforeList.items.map((item) => item.id), ['alpha-id', null]);
      expect(beforeList.items.map((item) => item.children.single.text), [
        'Alpha',
        'Before ',
      ]);
      expect(heading.id, isNull);
      expect(heading.children.single.text, 'Beta');
      expect(afterList.id, isNull);
      expect(afterList.items.map((item) => item.id), [null, 'gamma-id']);
      expect(afterList.items.map((item) => item.children.single.text), [
        ' After',
        'Gamma',
      ]);
      expect(result.metadata?.sourceBlockIndex, 0);
      expect(result.metadata?.sourceListItemIndex, 1);
      expect(result.metadata?.replacementCount, 3);
      expect(result.metadata?.selectedReplacementIndex, 1);
      expect(
        result.metadata?.identityRemapHints[1].blockIdentityAction,
        LessonSelectionSplitIdentityAction.reuseSourceListItemRuntimeIdentity,
      );
      _expectRoundTrip(result);
    },
  );

  test('converts a selected range into a bullet list item', () {
    const document = LessonDocument(
      blocks: [
        LessonParagraphBlock(children: [LessonTextRun('Alpha Beta Gamma')]),
      ],
    );

    final result = splitLessonDocumentSelection(
      document: document,
      target: const LessonTextBlockSelectionTarget(blockIndex: 0),
      start: 6,
      end: 10,
      conversion: const LessonSelectionBulletListConversion(),
    );

    expect(result.status, LessonSelectionSplitStatus.applied);
    expect(_blockTypes(result.document), [
      'paragraph',
      'bullet_list',
      'paragraph',
    ]);
    final selectedList = result.document.blocks[1] as LessonListBlock;
    expect(selectedList.items.single.children.single.text, 'Beta');
    expect(
      result.metadata?.selectedOutputTargetType,
      LessonSelectionSplitOutputTargetType.listItemText,
    );
    expect(
      result
          .metadata
          ?.identityRemapHints[1]
          .listItemIdentityHints
          .single
          .action,
      LessonSelectionSplitIdentityAction.reuseSourceBlockRuntimeIdentity,
    );
    _expectRoundTrip(result);
  });

  test(
    'ordered list conversion is deferred until start semantics are explicit',
    () {
      const document = LessonDocument(
        blocks: [
          LessonParagraphBlock(children: [LessonTextRun('Alpha Beta Gamma')]),
        ],
      );

      final result = splitLessonDocumentSelection(
        document: document,
        target: const LessonTextBlockSelectionTarget(blockIndex: 0),
        start: 6,
        end: 10,
        conversion: const LessonSelectionOrderedListConversion(),
      );

      expect(result.status, LessonSelectionSplitStatus.orderedListDeferred);
      expect(result.document, same(document));
      expect(result.metadata, isNull);
    },
  );
}

void _expectRoundTrip(LessonSelectionSplitResult result) {
  expect(result.status, LessonSelectionSplitStatus.applied);
  final parsed = LessonDocument.fromJson(result.document.toJson());
  expect(parsed.toJson(), result.document.toJson());
}

List<String> _blockTypes(LessonDocument document) {
  return document.blocks.map((block) => block.type).toList(growable: false);
}
