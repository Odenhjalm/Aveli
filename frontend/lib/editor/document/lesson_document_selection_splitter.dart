import 'lesson_document.dart';

enum LessonSelectionSplitStatus {
  applied,
  collapsedSelection,
  invalidRange,
  unsupportedTarget,
  orderedListDeferred,
}

enum LessonSelectionSplitOutputTargetType { blockText, listItemText }

enum LessonSelectionSplitIdentityAction {
  createRuntimeIdentity,
  reuseSourceBlockRuntimeIdentity,
  reuseSourceListItemRuntimeIdentity,
}

sealed class LessonSelectionSplitTarget {
  const LessonSelectionSplitTarget({required this.blockIndex});

  final int blockIndex;
}

final class LessonTextBlockSelectionTarget extends LessonSelectionSplitTarget {
  const LessonTextBlockSelectionTarget({required super.blockIndex});
}

final class LessonListItemSelectionTarget extends LessonSelectionSplitTarget {
  const LessonListItemSelectionTarget({
    required super.blockIndex,
    required this.itemIndex,
  });

  final int itemIndex;
}

sealed class LessonSelectionStructuralConversion {
  const LessonSelectionStructuralConversion();
}

final class LessonSelectionParagraphConversion
    extends LessonSelectionStructuralConversion {
  const LessonSelectionParagraphConversion();
}

final class LessonSelectionHeadingConversion
    extends LessonSelectionStructuralConversion {
  const LessonSelectionHeadingConversion({required this.level});

  final int level;
}

final class LessonSelectionBulletListConversion
    extends LessonSelectionStructuralConversion {
  const LessonSelectionBulletListConversion();
}

final class LessonSelectionOrderedListConversion
    extends LessonSelectionStructuralConversion {
  const LessonSelectionOrderedListConversion();
}

final class LessonSelectionSplitResult {
  const LessonSelectionSplitResult._({
    required this.status,
    required this.document,
    this.metadata,
  });

  factory LessonSelectionSplitResult.applied({
    required LessonDocument document,
    required LessonSelectionSplitMetadata metadata,
  }) {
    return LessonSelectionSplitResult._(
      status: LessonSelectionSplitStatus.applied,
      document: document,
      metadata: metadata,
    );
  }

  factory LessonSelectionSplitResult.rejected({
    required LessonSelectionSplitStatus status,
    required LessonDocument document,
  }) {
    assert(status != LessonSelectionSplitStatus.applied);
    return LessonSelectionSplitResult._(status: status, document: document);
  }

  final LessonSelectionSplitStatus status;
  final LessonDocument document;
  final LessonSelectionSplitMetadata? metadata;

  bool get applied => status == LessonSelectionSplitStatus.applied;
}

final class LessonSelectionSplitMetadata {
  const LessonSelectionSplitMetadata({
    required this.sourceBlockIndex,
    required this.sourceListItemIndex,
    required this.replacementCount,
    required this.selectedReplacementIndex,
    required this.selectedOutputTargetType,
    required this.identityRemapHints,
  });

  final int sourceBlockIndex;
  final int? sourceListItemIndex;
  final int replacementCount;
  final int selectedReplacementIndex;
  final LessonSelectionSplitOutputTargetType selectedOutputTargetType;
  final List<LessonSelectionSplitReplacementIdentityHint> identityRemapHints;
}

final class LessonSelectionSplitReplacementIdentityHint {
  const LessonSelectionSplitReplacementIdentityHint({
    required this.replacementIndex,
    required this.blockIdentityAction,
    this.sourceBlockIndex,
    this.sourceListItemIndex,
    this.listItemIdentityHints =
        const <LessonSelectionSplitListItemIdentityHint>[],
  });

  final int replacementIndex;
  final LessonSelectionSplitIdentityAction blockIdentityAction;
  final int? sourceBlockIndex;
  final int? sourceListItemIndex;
  final List<LessonSelectionSplitListItemIdentityHint> listItemIdentityHints;
}

final class LessonSelectionSplitListItemIdentityHint {
  const LessonSelectionSplitListItemIdentityHint({
    required this.itemIndex,
    required this.action,
    this.sourceListItemIndex,
  });

  final int itemIndex;
  final LessonSelectionSplitIdentityAction action;
  final int? sourceListItemIndex;
}

LessonSelectionSplitResult splitLessonDocumentSelection({
  required LessonDocument document,
  required LessonSelectionSplitTarget target,
  required int start,
  required int end,
  required LessonSelectionStructuralConversion conversion,
}) {
  if (conversion is LessonSelectionOrderedListConversion) {
    return LessonSelectionSplitResult.rejected(
      status: LessonSelectionSplitStatus.orderedListDeferred,
      document: document,
    );
  }
  if (target.blockIndex < 0 || target.blockIndex >= document.blocks.length) {
    return LessonSelectionSplitResult.rejected(
      status: LessonSelectionSplitStatus.invalidRange,
      document: document,
    );
  }
  return switch (target) {
    LessonTextBlockSelectionTarget() => _splitTextBlockSelection(
      document: document,
      target: target,
      start: start,
      end: end,
      conversion: conversion,
    ),
    LessonListItemSelectionTarget() => _splitListItemSelection(
      document: document,
      target: target,
      start: start,
      end: end,
      conversion: conversion,
    ),
  };
}

LessonSelectionSplitResult _splitTextBlockSelection({
  required LessonDocument document,
  required LessonTextBlockSelectionTarget target,
  required int start,
  required int end,
  required LessonSelectionStructuralConversion conversion,
}) {
  final block = document.blocks[target.blockIndex];
  final children = switch (block) {
    LessonParagraphBlock(:final children) => children,
    LessonHeadingBlock(:final children) => children,
    _ => null,
  };
  if (children == null) {
    return LessonSelectionSplitResult.rejected(
      status: LessonSelectionSplitStatus.unsupportedTarget,
      document: document,
    );
  }
  final range = _validatedRange(children, start: start, end: end);
  if (range == null) {
    return LessonSelectionSplitResult.rejected(
      status: LessonSelectionSplitStatus.invalidRange,
      document: document,
    );
  }
  if (range.collapsed) {
    return LessonSelectionSplitResult.rejected(
      status: LessonSelectionSplitStatus.collapsedSelection,
      document: document,
    );
  }

  final split = _splitRunsByRange(children, start: range.start, end: range.end);
  final replacement = _splitTextBlockIntoBlocks(
    source: block,
    split: split,
    conversion: conversion,
  );
  final replacementStart = _hasText(split.before) ? 1 : 0;
  final identityHints = _textBlockIdentityHints(
    sourceBlockIndex: target.blockIndex,
    selectedReplacementIndex: replacementStart,
    replacement: replacement,
  );

  return _appliedResult(
    document: document,
    sourceBlockIndex: target.blockIndex,
    sourceListItemIndex: null,
    replacement: replacement,
    selectedReplacementIndex: replacementStart,
    selectedOutputTargetType: _outputTargetTypeFor(conversion),
    identityHints: identityHints,
  );
}

LessonSelectionSplitResult _splitListItemSelection({
  required LessonDocument document,
  required LessonListItemSelectionTarget target,
  required int start,
  required int end,
  required LessonSelectionStructuralConversion conversion,
}) {
  final block = document.blocks[target.blockIndex];
  if (block is! LessonListBlock) {
    return LessonSelectionSplitResult.rejected(
      status: LessonSelectionSplitStatus.unsupportedTarget,
      document: document,
    );
  }
  if (block.type == 'ordered_list') {
    return LessonSelectionSplitResult.rejected(
      status: LessonSelectionSplitStatus.orderedListDeferred,
      document: document,
    );
  }
  if (target.itemIndex < 0 || target.itemIndex >= block.items.length) {
    return LessonSelectionSplitResult.rejected(
      status: LessonSelectionSplitStatus.invalidRange,
      document: document,
    );
  }
  final item = block.items[target.itemIndex];
  final range = _validatedRange(item.children, start: start, end: end);
  if (range == null) {
    return LessonSelectionSplitResult.rejected(
      status: LessonSelectionSplitStatus.invalidRange,
      document: document,
    );
  }
  if (range.collapsed) {
    return LessonSelectionSplitResult.rejected(
      status: LessonSelectionSplitStatus.collapsedSelection,
      document: document,
    );
  }

  final split = _splitRunsByRange(
    item.children,
    start: range.start,
    end: range.end,
  );
  final replacement = _splitListItemIntoBlocks(
    source: block,
    itemIndex: target.itemIndex,
    split: split,
    conversion: conversion,
  );
  final selectedReplacementIndex =
      _beforeListItemCount(itemIndex: target.itemIndex, split: split) > 0
      ? 1
      : 0;
  final identityHints = _listItemIdentityHints(
    sourceBlockIndex: target.blockIndex,
    sourceListItemIndex: target.itemIndex,
    source: block,
    split: split,
    selectedReplacementIndex: selectedReplacementIndex,
    replacement: replacement,
  );

  return _appliedResult(
    document: document,
    sourceBlockIndex: target.blockIndex,
    sourceListItemIndex: target.itemIndex,
    replacement: replacement,
    selectedReplacementIndex: selectedReplacementIndex,
    selectedOutputTargetType: _outputTargetTypeFor(conversion),
    identityHints: identityHints,
  );
}

LessonSelectionSplitResult _appliedResult({
  required LessonDocument document,
  required int sourceBlockIndex,
  required int? sourceListItemIndex,
  required List<LessonBlock> replacement,
  required int selectedReplacementIndex,
  required LessonSelectionSplitOutputTargetType selectedOutputTargetType,
  required List<LessonSelectionSplitReplacementIdentityHint> identityHints,
}) {
  final nextBlocks = List<LessonBlock>.from(document.blocks)
    ..removeAt(sourceBlockIndex)
    ..insertAll(sourceBlockIndex, replacement);
  final nextDocument = LessonDocument(
    blocks: List<LessonBlock>.unmodifiable(nextBlocks),
  );
  LessonDocument.fromJson(nextDocument.toJson());
  return LessonSelectionSplitResult.applied(
    document: nextDocument,
    metadata: LessonSelectionSplitMetadata(
      sourceBlockIndex: sourceBlockIndex,
      sourceListItemIndex: sourceListItemIndex,
      replacementCount: replacement.length,
      selectedReplacementIndex: selectedReplacementIndex,
      selectedOutputTargetType: selectedOutputTargetType,
      identityRemapHints:
          List<LessonSelectionSplitReplacementIdentityHint>.unmodifiable(
            identityHints,
          ),
    ),
  );
}

List<LessonBlock> _splitTextBlockIntoBlocks({
  required LessonBlock source,
  required _RunRangeSplit split,
  required LessonSelectionStructuralConversion conversion,
}) {
  final blocks = <LessonBlock>[];
  if (_hasText(split.before)) {
    blocks.add(_textBlockLike(source, split.before));
  }
  blocks.add(_convertedBlock(conversion, split.selected));
  if (_hasText(split.after)) {
    blocks.add(_textBlockLike(source, split.after));
  }
  return List<LessonBlock>.unmodifiable(blocks);
}

List<LessonBlock> _splitListItemIntoBlocks({
  required LessonListBlock source,
  required int itemIndex,
  required _RunRangeSplit split,
  required LessonSelectionStructuralConversion conversion,
}) {
  final beforeItems = <LessonListItem>[
    ...source.items.take(itemIndex),
    if (_hasText(split.before)) LessonListItem(children: split.before),
  ];
  final afterItems = <LessonListItem>[
    if (_hasText(split.after)) LessonListItem(children: split.after),
    ...source.items.skip(itemIndex + 1),
  ];
  return List<LessonBlock>.unmodifiable(<LessonBlock>[
    if (beforeItems.isNotEmpty) LessonListBlock.bullet(items: beforeItems),
    _convertedBlock(conversion, split.selected),
    if (afterItems.isNotEmpty) LessonListBlock.bullet(items: afterItems),
  ]);
}

LessonBlock _textBlockLike(LessonBlock source, List<LessonTextRun> children) {
  // Optional persisted ids are metadata, not editor runtime identity. A split
  // creates new canonical nodes, so source ids are intentionally not copied to
  // any generated fragment. Runtime identity reuse is reported separately.
  if (source is LessonHeadingBlock) {
    return LessonHeadingBlock(level: source.level, children: children);
  }
  return LessonParagraphBlock(children: children);
}

LessonBlock _convertedBlock(
  LessonSelectionStructuralConversion conversion,
  List<LessonTextRun> children,
) {
  return switch (conversion) {
    LessonSelectionParagraphConversion() => LessonParagraphBlock(
      children: children,
    ),
    LessonSelectionHeadingConversion(:final level) => LessonHeadingBlock(
      level: level,
      children: children,
    ),
    LessonSelectionBulletListConversion() => LessonListBlock.bullet(
      items: <LessonListItem>[LessonListItem(children: children)],
    ),
    LessonSelectionOrderedListConversion() => throw StateError(
      'Ordered-list selection splitting is deferred.',
    ),
  };
}

List<LessonSelectionSplitReplacementIdentityHint> _textBlockIdentityHints({
  required int sourceBlockIndex,
  required int selectedReplacementIndex,
  required List<LessonBlock> replacement,
}) {
  return List<LessonSelectionSplitReplacementIdentityHint>.unmodifiable([
    for (var index = 0; index < replacement.length; index += 1)
      if (index == selectedReplacementIndex &&
          replacement[index] is LessonListBlock)
        LessonSelectionSplitReplacementIdentityHint(
          replacementIndex: index,
          blockIdentityAction:
              LessonSelectionSplitIdentityAction.createRuntimeIdentity,
          listItemIdentityHints: const [
            LessonSelectionSplitListItemIdentityHint(
              itemIndex: 0,
              action: LessonSelectionSplitIdentityAction
                  .reuseSourceBlockRuntimeIdentity,
            ),
          ],
        )
      else
        LessonSelectionSplitReplacementIdentityHint(
          replacementIndex: index,
          blockIdentityAction: index == selectedReplacementIndex
              ? LessonSelectionSplitIdentityAction
                    .reuseSourceBlockRuntimeIdentity
              : LessonSelectionSplitIdentityAction.createRuntimeIdentity,
          sourceBlockIndex: index == selectedReplacementIndex
              ? sourceBlockIndex
              : null,
        ),
  ]);
}

List<LessonSelectionSplitReplacementIdentityHint> _listItemIdentityHints({
  required int sourceBlockIndex,
  required int sourceListItemIndex,
  required LessonListBlock source,
  required _RunRangeSplit split,
  required int selectedReplacementIndex,
  required List<LessonBlock> replacement,
}) {
  final hints = <LessonSelectionSplitReplacementIdentityHint>[];
  var replacementIndex = 0;
  final beforeCount = _beforeListItemCount(
    itemIndex: sourceListItemIndex,
    split: split,
  );
  if (beforeCount > 0) {
    hints.add(
      LessonSelectionSplitReplacementIdentityHint(
        replacementIndex: replacementIndex,
        blockIdentityAction:
            LessonSelectionSplitIdentityAction.reuseSourceBlockRuntimeIdentity,
        sourceBlockIndex: sourceBlockIndex,
        listItemIdentityHints: _beforeListItemHints(
          itemIndex: sourceListItemIndex,
          hasSplitBefore: _hasText(split.before),
        ),
      ),
    );
    replacementIndex += 1;
  }

  final selectedBlock = replacement[selectedReplacementIndex];
  hints.add(
    LessonSelectionSplitReplacementIdentityHint(
      replacementIndex: replacementIndex,
      blockIdentityAction: selectedBlock is LessonListBlock
          ? LessonSelectionSplitIdentityAction.createRuntimeIdentity
          : LessonSelectionSplitIdentityAction
                .reuseSourceListItemRuntimeIdentity,
      sourceListItemIndex: selectedBlock is LessonListBlock
          ? null
          : sourceListItemIndex,
      listItemIdentityHints: selectedBlock is LessonListBlock
          ? [
              LessonSelectionSplitListItemIdentityHint(
                itemIndex: 0,
                action: LessonSelectionSplitIdentityAction
                    .reuseSourceListItemRuntimeIdentity,
                sourceListItemIndex: sourceListItemIndex,
              ),
            ]
          : const <LessonSelectionSplitListItemIdentityHint>[],
    ),
  );
  replacementIndex += 1;

  final afterCount = _afterListItemCount(
    source: source,
    itemIndex: sourceListItemIndex,
    split: split,
  );
  if (afterCount > 0) {
    hints.add(
      LessonSelectionSplitReplacementIdentityHint(
        replacementIndex: replacementIndex,
        blockIdentityAction: beforeCount == 0
            ? LessonSelectionSplitIdentityAction.reuseSourceBlockRuntimeIdentity
            : LessonSelectionSplitIdentityAction.createRuntimeIdentity,
        sourceBlockIndex: beforeCount == 0 ? sourceBlockIndex : null,
        listItemIdentityHints: _afterListItemHints(
          itemIndex: sourceListItemIndex,
          hasSplitAfter: _hasText(split.after),
          sourceLength: source.items.length,
        ),
      ),
    );
  }
  return List<LessonSelectionSplitReplacementIdentityHint>.unmodifiable(hints);
}

List<LessonSelectionSplitListItemIdentityHint> _beforeListItemHints({
  required int itemIndex,
  required bool hasSplitBefore,
}) {
  return List<LessonSelectionSplitListItemIdentityHint>.unmodifiable([
    for (var index = 0; index < itemIndex; index += 1)
      LessonSelectionSplitListItemIdentityHint(
        itemIndex: index,
        action: LessonSelectionSplitIdentityAction
            .reuseSourceListItemRuntimeIdentity,
        sourceListItemIndex: index,
      ),
    if (hasSplitBefore)
      LessonSelectionSplitListItemIdentityHint(
        itemIndex: itemIndex,
        action: LessonSelectionSplitIdentityAction.createRuntimeIdentity,
      ),
  ]);
}

List<LessonSelectionSplitListItemIdentityHint> _afterListItemHints({
  required int itemIndex,
  required bool hasSplitAfter,
  required int sourceLength,
}) {
  var outputIndex = 0;
  return List<LessonSelectionSplitListItemIdentityHint>.unmodifiable([
    if (hasSplitAfter)
      LessonSelectionSplitListItemIdentityHint(
        itemIndex: outputIndex++,
        action: LessonSelectionSplitIdentityAction.createRuntimeIdentity,
      ),
    for (var index = itemIndex + 1; index < sourceLength; index += 1)
      LessonSelectionSplitListItemIdentityHint(
        itemIndex: outputIndex++,
        action: LessonSelectionSplitIdentityAction
            .reuseSourceListItemRuntimeIdentity,
        sourceListItemIndex: index,
      ),
  ]);
}

int _beforeListItemCount({
  required int itemIndex,
  required _RunRangeSplit split,
}) {
  return itemIndex + (_hasText(split.before) ? 1 : 0);
}

int _afterListItemCount({
  required LessonListBlock source,
  required int itemIndex,
  required _RunRangeSplit split,
}) {
  return (_hasText(split.after) ? 1 : 0) + source.items.length - itemIndex - 1;
}

LessonSelectionSplitOutputTargetType _outputTargetTypeFor(
  LessonSelectionStructuralConversion conversion,
) {
  return conversion is LessonSelectionBulletListConversion
      ? LessonSelectionSplitOutputTargetType.listItemText
      : LessonSelectionSplitOutputTargetType.blockText;
}

_SelectedRange? _validatedRange(
  List<LessonTextRun> runs, {
  required int start,
  required int end,
}) {
  final length = _plainTextLength(runs);
  if (start < 0 || end < 0 || start > length || end > length) {
    return null;
  }
  return start <= end
      ? _SelectedRange(start: start, end: end)
      : _SelectedRange(start: end, end: start);
}

_RunRangeSplit _splitRunsByRange(
  List<LessonTextRun> runs, {
  required int start,
  required int end,
}) {
  return _RunRangeSplit(
    before: _sliceRuns(runs, 0, start),
    selected: _sliceRuns(runs, start, end),
    after: _sliceRuns(runs, end, _plainTextLength(runs)),
  );
}

List<LessonTextRun> _sliceRuns(List<LessonTextRun> runs, int start, int end) {
  if (start >= end) return const <LessonTextRun>[];
  final output = <LessonTextRun>[];
  var offset = 0;
  for (final run in runs) {
    final runStart = offset;
    final runEnd = runStart + run.text.length;
    offset = runEnd;
    if (end <= runStart || start >= runEnd) {
      continue;
    }
    final localStart = start <= runStart ? 0 : start - runStart;
    final localEnd = end >= runEnd ? run.text.length : end - runStart;
    if (localStart == localEnd) {
      continue;
    }
    output.add(run.copyWith(text: run.text.substring(localStart, localEnd)));
  }
  return List<LessonTextRun>.unmodifiable(output);
}

bool _hasText(List<LessonTextRun> runs) => _plainTextLength(runs) > 0;

int _plainTextLength(List<LessonTextRun> runs) {
  return runs.fold<int>(0, (length, run) => length + run.text.length);
}

final class _SelectedRange {
  const _SelectedRange({required this.start, required this.end});

  final int start;
  final int end;

  bool get collapsed => start == end;
}

final class _RunRangeSplit {
  const _RunRangeSplit({
    required this.before,
    required this.selected,
    required this.after,
  });

  final List<LessonTextRun> before;
  final List<LessonTextRun> selected;
  final List<LessonTextRun> after;
}
