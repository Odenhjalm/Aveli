import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'lesson_document.dart';

class LessonDocumentEditor extends StatefulWidget {
  const LessonDocumentEditor({
    super.key,
    required this.document,
    required this.onChanged,
    this.media = const <LessonDocumentPreviewMedia>[],
    this.onInsertionIndexChanged,
    this.enabled = true,
    this.minHeight = 280,
  });

  final LessonDocument document;
  final ValueChanged<LessonDocument> onChanged;
  final List<LessonDocumentPreviewMedia> media;
  final ValueChanged<int>? onInsertionIndexChanged;
  final bool enabled;
  final double minHeight;

  @override
  State<LessonDocumentEditor> createState() => _LessonDocumentEditorState();
}

class _LessonDocumentEditorState extends State<LessonDocumentEditor> {
  final Map<String, _LessonTextEditingController> _controllers =
      <String, _LessonTextEditingController>{};
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};
  _EditorTarget _selectedTarget = const _EditorTarget.block(0);

  @override
  void didUpdateWidget(LessonDocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    final liveKeys = <String>{};
    final blocks = widget.document.blocks;
    if (blocks.isEmpty) {
      liveKeys.add(_EditorTarget.block(0).key);
      _syncControllerText(_EditorTarget.block(0).key, '');
    }
    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex += 1) {
      final block = blocks[blockIndex];
      if (block case LessonParagraphBlock(:final children)) {
        final key = _EditorTarget.block(blockIndex).key;
        liveKeys.add(key);
        _syncControllerText(key, _plainText(children), children);
      } else if (block case LessonHeadingBlock(:final children)) {
        final key = _EditorTarget.block(blockIndex).key;
        liveKeys.add(key);
        _syncControllerText(key, _plainText(children), children);
      } else if (block case LessonListBlock(:final items)) {
        for (var itemIndex = 0; itemIndex < items.length; itemIndex += 1) {
          final key = _EditorTarget.listItem(blockIndex, itemIndex).key;
          liveKeys.add(key);
          _syncControllerText(
            key,
            _plainText(items[itemIndex].children),
            items[itemIndex].children,
          );
        }
      } else if (block case LessonCtaBlock(:final label, :final targetUrl)) {
        final labelKey = 'cta_label_$blockIndex';
        final urlKey = 'cta_url_$blockIndex';
        liveKeys.add(labelKey);
        liveKeys.add(urlKey);
        _syncControllerText(labelKey, label);
        _syncControllerText(urlKey, targetUrl);
      }
    }

    final staleKeys = _controllers.keys
        .where((key) => !liveKeys.contains(key))
        .toList(growable: false);
    for (final key in staleKeys) {
      _controllers.remove(key)?.dispose();
      _focusNodes.remove(key)?.dispose();
    }
  }

  void _syncControllerText(
    String key,
    String text, [
    List<LessonTextRun> runs = const <LessonTextRun>[],
  ]) {
    final controller = _controllers[key];
    if (controller == null) return;
    controller.setRuns(runs);
    final focusNode = _focusNodes[key];
    if (controller.text == text || (focusNode?.hasFocus ?? false)) {
      return;
    }
    controller.text = text;
  }

  _LessonTextEditingController _controllerFor(
    String key,
    String text, [
    List<LessonTextRun> runs = const <LessonTextRun>[],
  ]) {
    final controller = _controllers.putIfAbsent(
      key,
      () => _LessonTextEditingController(text: text, runs: runs),
    );
    controller.setRuns(runs);
    return controller;
  }

  FocusNode _focusNodeFor(String key, _EditorTarget target) {
    return _focusNodes.putIfAbsent(key, () {
      final node = FocusNode();
      node.addListener(() {
        if (node.hasFocus && mounted) {
          _select(target);
        }
      });
      return node;
    });
  }

  void _emit(LessonDocument document) {
    if (!widget.enabled) return;
    widget.onChanged(document);
  }

  void _select(_EditorTarget target) {
    widget.onInsertionIndexChanged?.call(
      target.insertionIndex(widget.document),
    );
    if (_selectedTarget == target) return;
    setState(() => _selectedTarget = target);
  }

  void _replaceTargetText(_EditorTarget target, String text) {
    final normalizedText = text.replaceAll('\r\n', '\n');
    final blocks = widget.document.blocks.isEmpty
        ? <LessonBlock>[
            const LessonParagraphBlock(
              children: <LessonTextRun>[LessonTextRun('')],
            ),
          ]
        : widget.document.blocks;
    final nextBlocks = List<LessonBlock>.from(blocks);
    final block = nextBlocks[target.blockIndex];
    if (target.itemIndex case final itemIndex?) {
      if (block is! LessonListBlock) return;
      final nextItems = List<LessonListItem>.from(block.items);
      final item = nextItems[itemIndex];
      nextItems[itemIndex] = item.copyWith(
        children: _textRunsForReplacement(item.children, normalizedText),
      );
      nextBlocks[target.blockIndex] = block.copyWith(items: nextItems);
    } else if (block is LessonParagraphBlock) {
      nextBlocks[target.blockIndex] = block.copyWith(
        children: _textRunsForReplacement(block.children, normalizedText),
      );
    } else if (block is LessonHeadingBlock) {
      nextBlocks[target.blockIndex] = block.copyWith(
        children: _textRunsForReplacement(block.children, normalizedText),
      );
    } else {
      return;
    }
    _emit(LessonDocument(blocks: List<LessonBlock>.unmodifiable(nextBlocks)));
  }

  void _applyInlineMark(LessonInlineMark mark) {
    final selection = _selectedTextRange();
    if (selection == null) return;
    final target = selection.target;
    _emit(
      target.itemIndex == null
          ? widget.document.formatBlockInlineRange(
              target.blockIndex,
              start: selection.start,
              end: selection.end,
              mark: mark,
            )
          : widget.document.formatListItemInlineRange(
              target.blockIndex,
              itemIndex: target.itemIndex!,
              start: selection.start,
              end: selection.end,
              mark: mark,
            ),
    );
  }

  void _clearFormatting() {
    final selection = _selectedTextRange();
    if (selection == null) return;
    final target = selection.target;
    _emit(
      target.itemIndex == null
          ? widget.document.clearBlockInlineFormatting(
              target.blockIndex,
              start: selection.start,
              end: selection.end,
            )
          : widget.document.clearListItemInlineFormatting(
              target.blockIndex,
              itemIndex: target.itemIndex!,
              start: selection.start,
              end: selection.end,
            ),
    );
  }

  List<LessonTextRun> _childrenForTarget(_EditorTarget target) {
    final blocks = widget.document.blocks.isEmpty
        ? const <LessonBlock>[
            LessonParagraphBlock(children: <LessonTextRun>[LessonTextRun('')]),
          ]
        : widget.document.blocks;
    final block = blocks[target.blockIndex];
    if (target.itemIndex case final itemIndex?) {
      return (block as LessonListBlock).items[itemIndex].children;
    }
    if (block is LessonParagraphBlock) return block.children;
    if (block is LessonHeadingBlock) return block.children;
    return const <LessonTextRun>[];
  }

  void _convertSelectedBlock(_BlockConversion conversion) {
    final selection = _selectedTextRange();
    if (selection == null) return;
    final sourceBlocks = widget.document.blocks.isEmpty
        ? const <LessonBlock>[
            LessonParagraphBlock(children: <LessonTextRun>[LessonTextRun('')]),
          ]
        : widget.document.blocks;
    final normalizedTarget = selection.target;
    final block = sourceBlocks[normalizedTarget.blockIndex];
    final split = _splitRunsByRange(
      _childrenForTarget(normalizedTarget),
      start: selection.start,
      end: selection.end,
    );
    final nextBlocks = List<LessonBlock>.from(sourceBlocks);

    if (normalizedTarget.itemIndex case final itemIndex?) {
      if (block is! LessonListBlock) return;
      final replacement = _splitListItemSelectionIntoBlocks(
        block,
        itemIndex: itemIndex,
        split: split,
        conversion: conversion,
      );
      nextBlocks
        ..removeAt(normalizedTarget.blockIndex)
        ..insertAll(normalizedTarget.blockIndex, replacement);
    } else {
      final replacement = _splitTextBlockSelectionIntoBlocks(
        block,
        split: split,
        conversion: conversion,
      );
      nextBlocks
        ..removeAt(normalizedTarget.blockIndex)
        ..insertAll(normalizedTarget.blockIndex, replacement);
    }
    _emit(LessonDocument(blocks: List<LessonBlock>.unmodifiable(nextBlocks)));
  }

  _SelectedTextRange? _selectedTextRange() {
    final target = _selectedTarget.normalized(widget.document);
    if (target == null) return null;
    final children = _childrenForTarget(target);
    final length = _plainText(children).length;
    if (length == 0) return null;
    final controller = _controllers[target.key];
    final selection = controller?.selection;
    if (selection == null || !selection.isValid || selection.isCollapsed) {
      return null;
    }
    final start = selection.start.clamp(0, length).toInt();
    final end = selection.end.clamp(0, length).toInt();
    if (start == end) return null;
    return _SelectedTextRange(
      target: target,
      start: start < end ? start : end,
      end: end > start ? end : start,
    );
  }

  void _appendParagraph() {
    final next = widget.document.insertParagraph(
      widget.document.blocks.length,
      const <LessonTextRun>[LessonTextRun('')],
    );
    _emit(next);
    setState(
      () => _selectedTarget = _EditorTarget.block(next.blocks.length - 1),
    );
  }

  void _moveBlock(int blockIndex, int targetIndex) {
    if (!widget.enabled) return;
    if (blockIndex < 0 || blockIndex >= widget.document.blocks.length) return;
    if (targetIndex < 0 || targetIndex >= widget.document.blocks.length) {
      return;
    }
    if (blockIndex == targetIndex) return;
    final next = widget.document.moveBlock(blockIndex, targetIndex);
    _emit(next);
    final nextTarget = _EditorTarget.block(targetIndex);
    widget.onInsertionIndexChanged?.call(nextTarget.insertionIndex(next));
    setState(() => _selectedTarget = nextTarget);
  }

  void _moveBlockUp(int blockIndex) {
    _moveBlock(blockIndex, blockIndex - 1);
  }

  void _moveBlockDown(int blockIndex) {
    _moveBlock(blockIndex, blockIndex + 1);
  }

  void _updateCtaBlock(int blockIndex, {String? label, String? targetUrl}) {
    final block = widget.document.blocks[blockIndex];
    if (block is! LessonCtaBlock) return;
    final nextBlocks = List<LessonBlock>.from(widget.document.blocks);
    nextBlocks[blockIndex] = LessonCtaBlock(
      id: block.id,
      label: label ?? block.label,
      targetUrl: targetUrl ?? block.targetUrl,
    );
    _emit(LessonDocument(blocks: List<LessonBlock>.unmodifiable(nextBlocks)));
  }

  @override
  Widget build(BuildContext context) {
    _syncControllers();
    final blocks = widget.document.blocks.isEmpty
        ? const <LessonBlock>[
            LessonParagraphBlock(children: <LessonTextRun>[LessonTextRun('')]),
          ]
        : widget.document.blocks;
    return Container(
      key: const ValueKey<String>('lesson_document_editor_shell'),
      constraints: BoxConstraints(minHeight: widget.minHeight),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Toolbar(
            enabled: widget.enabled,
            onBold: () => _applyInlineMark(LessonInlineMark.bold),
            onItalic: () => _applyInlineMark(LessonInlineMark.italic),
            onUnderline: () => _applyInlineMark(LessonInlineMark.underline),
            onClearFormatting: _clearFormatting,
            onParagraph: () =>
                _convertSelectedBlock(_BlockConversion.paragraph),
            onHeading: () => _convertSelectedBlock(_BlockConversion.heading),
            onBulletList: () =>
                _convertSelectedBlock(_BlockConversion.bulletList),
            onOrderedList: () =>
                _convertSelectedBlock(_BlockConversion.orderedList),
            onAddParagraph: _appendParagraph,
          ),
          const Divider(height: 1),
          Expanded(
            child: DecoratedBox(
              key: const ValueKey<String>(
                'lesson_document_continuous_writing_surface',
              ),
              decoration: const BoxDecoration(color: Colors.white),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: blocks.length,
                itemBuilder: (context, blockIndex) {
                  final block = blocks[blockIndex];
                  return _buildBlockEditor(context, block, blockIndex);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _paragraphStyle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.bodyLarge?.copyWith(
          height: 1.48,
          color: theme.colorScheme.onSurface,
        ) ??
        TextStyle(height: 1.48, color: theme.colorScheme.onSurface);
  }

  TextStyle _headingStyle(BuildContext context, int level) {
    final theme = Theme.of(context);
    final base = switch (level) {
      1 => theme.textTheme.headlineMedium,
      2 => theme.textTheme.headlineSmall,
      3 => theme.textTheme.titleLarge,
      _ => theme.textTheme.titleMedium,
    };
    return base?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.22,
          color: theme.colorScheme.onSurface,
        ) ??
        TextStyle(
          fontSize: level <= 2 ? 24 : 20,
          fontWeight: FontWeight.w700,
          height: 1.22,
          color: theme.colorScheme.onSurface,
        );
  }

  TextStyle _listMarkerStyle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.bodyLarge?.copyWith(
          height: 1.48,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ) ??
        TextStyle(
          height: 1.48,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        );
  }

  EdgeInsets _blockPadding(LessonBlock block, int blockIndex) {
    final top = blockIndex == 0 ? 0.0 : 6.0;
    final bottom = switch (block) {
      LessonHeadingBlock() => 8.0,
      LessonMediaBlock() || LessonCtaBlock() => 14.0,
      _ => 4.0,
    };
    return EdgeInsets.only(top: top, bottom: bottom);
  }

  Widget _buildFlowingBlockPadding({
    required LessonBlock block,
    required int blockIndex,
    required Widget child,
  }) {
    return Padding(padding: _blockPadding(block, blockIndex), child: child);
  }

  LessonDocumentPreviewMedia? _mediaForBlock(LessonMediaBlock block) {
    for (final media in widget.media) {
      if (media.lessonMediaId == block.lessonMediaId &&
          media.mediaType == block.mediaType) {
        return media;
      }
    }
    return null;
  }

  String _mediaFileName(LessonDocumentPreviewMedia? media) {
    final label = media?.label?.trim();
    if (label != null && label.isNotEmpty) return label;
    return 'Namnlös fil';
  }

  String _mediaTypeLabel(String mediaType) {
    return switch (mediaType) {
      'image' => 'image',
      'audio' => 'audio',
      'video' => 'video',
      'document' => 'document',
      _ => 'media',
    };
  }

  Widget _buildBlockEditor(
    BuildContext context,
    LessonBlock block,
    int blockIndex,
  ) {
    if (block is LessonParagraphBlock) {
      return _buildFlowingBlockPadding(
        block: block,
        blockIndex: blockIndex,
        child: _buildTextField(
          context,
          target: _EditorTarget.block(blockIndex),
          semanticsLabel: 'Stycke',
          children: block.children,
          textStyle: _paragraphStyle(context),
        ),
      );
    }
    if (block is LessonHeadingBlock) {
      return _buildFlowingBlockPadding(
        block: block,
        blockIndex: blockIndex,
        child: _buildTextField(
          context,
          target: _EditorTarget.block(blockIndex),
          semanticsLabel: 'Rubrik H${block.level}',
          children: block.children,
          textStyle: _headingStyle(context, block.level),
        ),
      );
    }
    if (block is LessonListBlock) {
      final ordered = block.type == 'ordered_list';
      return _buildFlowingBlockPadding(
        block: block,
        blockIndex: blockIndex,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (
              var itemIndex = 0;
              itemIndex < block.items.length;
              itemIndex += 1
            )
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 34,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          ordered ? '${itemIndex + (block.start ?? 1)}.' : '-',
                          textAlign: TextAlign.right,
                          style: _listMarkerStyle(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        context,
                        target: _EditorTarget.listItem(blockIndex, itemIndex),
                        semanticsLabel: ordered
                            ? 'Numrerad listpunkt ${itemIndex + 1}'
                            : 'Punktlista listpunkt ${itemIndex + 1}',
                        children: block.items[itemIndex].children,
                        textStyle: _paragraphStyle(context),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    if (block is LessonMediaBlock) {
      final theme = Theme.of(context);
      final media = _mediaForBlock(block);
      final fileName = _mediaFileName(media);
      final mediaTypeLabel = _mediaTypeLabel(block.mediaType);
      final canMoveUp = widget.enabled && blockIndex > 0;
      final canMoveDown =
          widget.enabled && blockIndex < widget.document.blocks.length - 1;
      return _buildFlowingBlockPadding(
        block: block,
        blockIndex: blockIndex,
        child: Padding(
          key: ValueKey<String>('lesson_document_media_$blockIndex'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.perm_media_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    Text(
                      mediaTypeLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: ValueKey<String>(
                      'lesson_document_media_move_up_$blockIndex',
                    ),
                    tooltip: 'Flytta media upp',
                    onPressed: canMoveUp
                        ? () => _moveBlockUp(blockIndex)
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    key: ValueKey<String>(
                      'lesson_document_media_move_down_$blockIndex',
                    ),
                    tooltip: 'Flytta media ned',
                    onPressed: canMoveDown
                        ? () => _moveBlockDown(blockIndex)
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (block is LessonCtaBlock) {
      final theme = Theme.of(context);
      return _buildFlowingBlockPadding(
        block: block,
        blockIndex: blockIndex,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CTA',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextField(
                key: ValueKey<String>('lesson_document_cta_label_$blockIndex'),
                enabled: widget.enabled,
                controller: _controllerFor(
                  'cta_label_$blockIndex',
                  block.label,
                ),
                style: _paragraphStyle(context),
                decoration: const InputDecoration(
                  hintText: 'CTA text',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (value) => _updateCtaBlock(blockIndex, label: value),
              ),
              TextField(
                key: ValueKey<String>('lesson_document_cta_url_$blockIndex'),
                enabled: widget.enabled,
                controller: _controllerFor(
                  'cta_url_$blockIndex',
                  block.targetUrl,
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
                decoration: const InputDecoration(
                  hintText: 'CTA URL',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (value) =>
                    _updateCtaBlock(blockIndex, targetUrl: value),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildTextField(
    BuildContext context, {
    required _EditorTarget target,
    required String semanticsLabel,
    required List<LessonTextRun> children,
    required TextStyle textStyle,
  }) {
    final key = target.key;
    final controller = _controllerFor(key, _plainText(children), children);
    final focusNode = _focusNodeFor(key, target);
    return Semantics(
      label: semanticsLabel,
      textField: true,
      child: TextField(
        key: ValueKey<String>('lesson_document_editor_$key'),
        enabled: widget.enabled,
        controller: controller,
        focusNode: focusNode,
        style: textStyle,
        minLines: 1,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          hintText: semanticsLabel,
          hintStyle: textStyle.copyWith(
            color: textStyle.color?.withValues(alpha: 0.34),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        onTap: () => _select(target),
        onChanged: (value) => _replaceTargetText(target, value),
      ),
    );
  }
}

class _LessonTextEditingController extends TextEditingController {
  _LessonTextEditingController({
    required String text,
    List<LessonTextRun> runs = const <LessonTextRun>[],
  }) : _runs = runs,
       super(text: text);

  List<LessonTextRun> _runs;

  void setRuns(List<LessonTextRun> runs) {
    _runs = List<LessonTextRun>.unmodifiable(runs);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? DefaultTextStyle.of(context).style;
    if (_runs.isEmpty || _plainText(_runs) != text) {
      return TextSpan(style: base, text: text);
    }
    return TextSpan(
      style: base,
      children: [
        for (final run in _runs)
          TextSpan(text: run.text, style: _styleForMarks(base, run)),
      ],
    );
  }
}

typedef LessonDocumentPreviewMediaBuilder =
    Widget Function(
      BuildContext context,
      LessonMediaBlock block,
      LessonDocumentPreviewMedia? media,
    );

enum LessonDocumentReadingMode { glass, paper }

class LessonDocumentReadingModeToggle extends StatelessWidget {
  const LessonDocumentReadingModeToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final LessonDocumentReadingMode value;
  final ValueChanged<LessonDocumentReadingMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Reading mode',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        ToggleButtons(
          key: const ValueKey<String>('lesson_document_reading_mode_toggle'),
          borderRadius: BorderRadius.circular(999),
          constraints: const BoxConstraints(minHeight: 36, minWidth: 82),
          isSelected: [
            value == LessonDocumentReadingMode.glass,
            value == LessonDocumentReadingMode.paper,
          ],
          onPressed: (index) {
            onChanged(
              index == 0
                  ? LessonDocumentReadingMode.glass
                  : LessonDocumentReadingMode.paper,
            );
          },
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Glass'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Paper'),
            ),
          ],
        ),
      ],
    );
  }
}

class LessonDocumentPreview extends StatelessWidget {
  const LessonDocumentPreview({
    super.key,
    required this.document,
    this.media = const <LessonDocumentPreviewMedia>[],
    this.mediaBuilder,
    this.onLaunchUrl,
    this.readingMode = LessonDocumentReadingMode.glass,
  });

  final LessonDocument document;
  final List<LessonDocumentPreviewMedia> media;
  final LessonDocumentPreviewMediaBuilder? mediaBuilder;
  final ValueChanged<String>? onLaunchUrl;
  final LessonDocumentReadingMode readingMode;

  @override
  Widget build(BuildContext context) {
    final preview = _buildPreviewContent(context);
    return switch (readingMode) {
      LessonDocumentReadingMode.glass => preview,
      LessonDocumentReadingMode.paper => _PaperReadingSurface(child: preview),
    };
  }

  Widget _buildPreviewContent(BuildContext context) {
    if (document.blocks.isEmpty) {
      return const Text('Lektionsinnehall saknas.');
    }
    final mediaByLessonMediaId = {
      for (final item in media) item.lessonMediaId: item,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in document.blocks) ...[
          _PreviewBlock(
            block: block,
            mediaByLessonMediaId: mediaByLessonMediaId,
            mediaBuilder: mediaBuilder,
            onLaunchUrl: onLaunchUrl,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _PaperReadingSurface extends StatelessWidget {
  const _PaperReadingSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle =
        theme.textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF151515),
          height: 1.5,
        ) ??
        const TextStyle(color: Color(0xFF151515), height: 1.5);

    return DecoratedBox(
      key: const ValueKey<String>('lesson_document_paper_reading_surface'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _PaperLinesPainter()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
              child: DefaultTextStyle.merge(style: textStyle, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaperLinesPainter extends CustomPainter {
  const _PaperLinesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = 1;
    for (var y = 30.0; y < size.height; y += 28.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PaperLinesPainter oldDelegate) => false;
}

class LessonDocumentPreviewMedia {
  const LessonDocumentPreviewMedia({
    required this.lessonMediaId,
    required this.mediaType,
    required this.state,
    this.label,
    this.resolvedUrl,
  });

  final String lessonMediaId;
  final String mediaType;
  final String state;
  final String? label;
  final String? resolvedUrl;
}

class _PreviewBlock extends StatelessWidget {
  const _PreviewBlock({
    required this.block,
    required this.mediaByLessonMediaId,
    required this.mediaBuilder,
    required this.onLaunchUrl,
  });

  final LessonBlock block;
  final Map<String, LessonDocumentPreviewMedia> mediaByLessonMediaId;
  final LessonDocumentPreviewMediaBuilder? mediaBuilder;
  final ValueChanged<String>? onLaunchUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (block is LessonParagraphBlock) {
      return _InlineRunsView(
        children: (block as LessonParagraphBlock).children,
        onLaunchUrl: onLaunchUrl,
      );
    }
    if (block is LessonHeadingBlock) {
      final heading = block as LessonHeadingBlock;
      return DefaultTextStyle.merge(
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        child: _InlineRunsView(
          children: heading.children,
          onLaunchUrl: onLaunchUrl,
        ),
      );
    }
    if (block is LessonListBlock) {
      final list = block as LessonListBlock;
      final ordered = list.type == 'ordered_list';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < list.items.length; index += 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      ordered ? '${index + (list.start ?? 1)}.' : '-',
                    ),
                  ),
                  Expanded(
                    child: _InlineRunsView(
                      children: list.items[index].children,
                      onLaunchUrl: onLaunchUrl,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    if (block is LessonMediaBlock) {
      final media = block as LessonMediaBlock;
      final builder = mediaBuilder;
      if (builder != null) {
        return builder(
          context,
          media,
          mediaByLessonMediaId[media.lessonMediaId],
        );
      }
      return _PreviewMediaBlock(
        block: media,
        media: mediaByLessonMediaId[media.lessonMediaId],
      );
    }
    if (block is LessonCtaBlock) {
      final cta = block as LessonCtaBlock;
      return FilledButton(
        onPressed: onLaunchUrl == null
            ? null
            : () => onLaunchUrl?.call(cta.targetUrl),
        child: Text(cta.label),
      );
    }
    return const SizedBox.shrink();
  }
}

class _PreviewMediaBlock extends StatelessWidget {
  const _PreviewMediaBlock({required this.block, required this.media});

  final LessonMediaBlock block;
  final LessonDocumentPreviewMedia? media;

  @override
  Widget build(BuildContext context) {
    final resolved = media;
    final typeMatches = resolved?.mediaType == block.mediaType;
    final title = typeMatches ? 'Infogad media' : 'Media kunde inte laddas';
    final label = resolved?.label?.trim();
    final resolvedUrl = resolved?.resolvedUrl?.trim();
    final subtitleLines = [
      if (label != null && label.isNotEmpty) label,
      if (typeMatches) 'Sparad media' else 'Kontrollera media i lektionen.',
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(_iconForMediaType(block.mediaType)),
            title: Text(title),
            subtitle: Text(subtitleLines.join('\n')),
          ),
          if (typeMatches &&
              block.mediaType == 'image' &&
              resolvedUrl != null &&
              resolvedUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
              child: Image.network(
                resolvedUrl,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconForMediaType(String mediaType) {
    return switch (mediaType) {
      'image' => Icons.image_outlined,
      'audio' => Icons.audiotrack_outlined,
      'video' => Icons.movie_creation_outlined,
      'document' => Icons.picture_as_pdf_outlined,
      _ => Icons.perm_media_outlined,
    };
  }
}

class _InlineRunsView extends StatelessWidget {
  const _InlineRunsView({required this.children, this.onLaunchUrl});

  final List<LessonTextRun> children;
  final ValueChanged<String>? onLaunchUrl;

  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    return RichText(
      text: TextSpan(
        style: defaultStyle,
        children: [
          for (final run in children)
            TextSpan(
              text: run.text,
              style: _styleForMarks(defaultStyle, run),
              recognizer: _recognizerForRun(run),
            ),
        ],
      ),
    );
  }

  GestureRecognizer? _recognizerForRun(LessonTextRun run) {
    final launch = onLaunchUrl;
    if (launch == null) return null;
    for (final mark in run.marks) {
      if (mark is LessonLinkMark) {
        return TapGestureRecognizer()..onTap = () => launch(mark.href);
      }
    }
    return null;
  }
}

TextStyle _styleForMarks(TextStyle base, LessonTextRun run) {
  var style = base;
  for (final mark in run.marks) {
    switch (mark.type) {
      case 'bold':
        style = style.copyWith(fontWeight: FontWeight.w700);
        break;
      case 'italic':
        style = style.copyWith(fontStyle: FontStyle.italic);
        break;
      case 'underline':
        style = style.copyWith(decoration: TextDecoration.underline);
        break;
      case 'link':
        style = style.copyWith(
          color: Colors.blueAccent,
          decoration: TextDecoration.underline,
        );
        break;
    }
  }
  return style;
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.enabled,
    required this.onBold,
    required this.onItalic,
    required this.onUnderline,
    required this.onClearFormatting,
    required this.onParagraph,
    required this.onHeading,
    required this.onBulletList,
    required this.onOrderedList,
    required this.onAddParagraph,
  });

  final bool enabled;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onUnderline;
  final VoidCallback onClearFormatting;
  final VoidCallback onParagraph;
  final VoidCallback onHeading;
  final VoidCallback onBulletList;
  final VoidCallback onOrderedList;
  final VoidCallback onAddParagraph;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          _toolbarButton(
            key: const Key('lesson_document_toolbar_bold'),
            icon: Icons.format_bold_rounded,
            label: 'Fet',
            onPressed: onBold,
          ),
          _toolbarButton(
            key: const Key('lesson_document_toolbar_italic'),
            icon: Icons.format_italic_rounded,
            label: 'Kursiv',
            onPressed: onItalic,
          ),
          _toolbarButton(
            key: const Key('lesson_document_toolbar_underline'),
            icon: Icons.format_underlined_rounded,
            label: 'Under',
            onPressed: onUnderline,
          ),
          _toolbarButton(
            key: const Key('lesson_document_toolbar_clear'),
            icon: Icons.format_clear_rounded,
            label: 'Rensa',
            onPressed: onClearFormatting,
          ),
          const VerticalDivider(width: 18),
          _toolbarButton(
            key: const Key('lesson_document_toolbar_paragraph'),
            icon: Icons.notes_outlined,
            label: 'Stycke',
            onPressed: onParagraph,
          ),
          _toolbarButton(
            key: const Key('lesson_document_toolbar_heading'),
            icon: Icons.title_rounded,
            label: 'Rubrik',
            onPressed: onHeading,
          ),
          _toolbarButton(
            key: const Key('lesson_document_toolbar_bullet_list'),
            icon: Icons.format_list_bulleted_rounded,
            label: 'Punkt',
            onPressed: onBulletList,
          ),
          _toolbarButton(
            key: const Key('lesson_document_toolbar_ordered_list'),
            icon: Icons.format_list_numbered_rounded,
            label: 'Nummer',
            onPressed: onOrderedList,
          ),
          const VerticalDivider(width: 18),
          _toolbarButton(
            key: const Key('lesson_document_toolbar_add_paragraph'),
            icon: Icons.add_rounded,
            label: 'Nytt stycke',
            onPressed: onAddParagraph,
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: OutlinedButton.icon(
        key: key,
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

enum _BlockConversion { paragraph, heading, bulletList, orderedList }

class _SelectedTextRange {
  const _SelectedTextRange({
    required this.target,
    required this.start,
    required this.end,
  });

  final _EditorTarget target;
  final int start;
  final int end;
}

class _EditorTarget {
  const _EditorTarget.block(this.blockIndex) : itemIndex = null;
  const _EditorTarget.listItem(this.blockIndex, this.itemIndex);

  final int blockIndex;
  final int? itemIndex;

  String get key => itemIndex == null
      ? 'block_$blockIndex'
      : 'block_${blockIndex}_item_$itemIndex';

  _EditorTarget? normalized(LessonDocument document) {
    if (document.blocks.isEmpty) {
      return const _EditorTarget.block(0);
    }
    if (blockIndex < 0 || blockIndex >= document.blocks.length) {
      return null;
    }
    final itemIndex = this.itemIndex;
    if (itemIndex == null) return this;
    final block = document.blocks[blockIndex];
    if (block is! LessonListBlock ||
        itemIndex < 0 ||
        itemIndex >= block.items.length) {
      return null;
    }
    return this;
  }

  int insertionIndex(LessonDocument document) {
    if (document.blocks.isEmpty) {
      return 0;
    }
    final target = normalized(document);
    if (target == null) {
      return document.blocks.length;
    }
    return (target.blockIndex + 1).clamp(0, document.blocks.length).toInt();
  }

  @override
  bool operator ==(Object other) {
    return other is _EditorTarget &&
        other.blockIndex == blockIndex &&
        other.itemIndex == itemIndex;
  }

  @override
  int get hashCode => Object.hash(blockIndex, itemIndex);
}

class _RunRangeSplit {
  const _RunRangeSplit({
    required this.before,
    required this.selected,
    required this.after,
  });

  final List<LessonTextRun> before;
  final List<LessonTextRun> selected;
  final List<LessonTextRun> after;
}

_RunRangeSplit _splitRunsByRange(
  List<LessonTextRun> runs, {
  required int start,
  required int end,
}) {
  return _RunRangeSplit(
    before: _sliceRuns(runs, 0, start),
    selected: _sliceRuns(runs, start, end),
    after: _sliceRuns(runs, end, _plainText(runs).length),
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

bool _hasText(List<LessonTextRun> runs) {
  return _plainText(runs).isNotEmpty;
}

List<LessonBlock> _splitTextBlockSelectionIntoBlocks(
  LessonBlock source, {
  required _RunRangeSplit split,
  required _BlockConversion conversion,
}) {
  final blocks = <LessonBlock>[];
  if (_hasText(split.before)) {
    blocks.add(_textBlockLike(source, split.before));
  }
  blocks.add(_convertedBlock(conversion, split.selected));
  if (_hasText(split.after)) {
    blocks.add(_textBlockLike(source, split.after));
  }
  return blocks;
}

List<LessonBlock> _splitListItemSelectionIntoBlocks(
  LessonListBlock source, {
  required int itemIndex,
  required _RunRangeSplit split,
  required _BlockConversion conversion,
}) {
  final selectedItem = source.items[itemIndex];
  final beforeItems = <LessonListItem>[
    ...source.items.take(itemIndex),
    if (_hasText(split.before)) selectedItem.copyWith(children: split.before),
  ];
  final afterItems = <LessonListItem>[
    if (_hasText(split.after)) selectedItem.copyWith(children: split.after),
    ...source.items.skip(itemIndex + 1),
  ];
  return <LessonBlock>[
    if (beforeItems.isNotEmpty) _listBlockLike(source, beforeItems),
    _convertedBlock(conversion, split.selected),
    if (afterItems.isNotEmpty) _listBlockLike(source, afterItems),
  ];
}

LessonBlock _textBlockLike(LessonBlock source, List<LessonTextRun> children) {
  if (source is LessonHeadingBlock) {
    return LessonHeadingBlock(level: source.level, children: children);
  }
  return LessonParagraphBlock(children: children);
}

LessonListBlock _listBlockLike(
  LessonListBlock source,
  List<LessonListItem> items,
) {
  if (source.type == 'ordered_list') {
    return LessonListBlock.ordered(start: source.start ?? 1, items: items);
  }
  return LessonListBlock.bullet(items: items);
}

LessonBlock _convertedBlock(
  _BlockConversion conversion,
  List<LessonTextRun> children,
) {
  return switch (conversion) {
    _BlockConversion.paragraph => LessonParagraphBlock(children: children),
    _BlockConversion.heading => LessonHeadingBlock(
      level: 2,
      children: children,
    ),
    _BlockConversion.bulletList => LessonListBlock.bullet(
      items: <LessonListItem>[LessonListItem(children: children)],
    ),
    _BlockConversion.orderedList => LessonListBlock.ordered(
      items: <LessonListItem>[LessonListItem(children: children)],
    ),
  };
}

List<LessonTextRun> _textRunsForReplacement(
  List<LessonTextRun> previous,
  String text,
) {
  final marks = _uniformMarks(previous);
  return <LessonTextRun>[
    LessonTextRun(
      text,
      marks: text.isEmpty ? const <LessonInlineMark>[] : marks,
    ),
  ];
}

List<LessonInlineMark> _uniformMarks(List<LessonTextRun> runs) {
  if (runs.isEmpty) return const <LessonInlineMark>[];
  final first = runs.first.marks;
  for (final run in runs.skip(1)) {
    if (!_sameMarkTypes(first, run.marks)) {
      return const <LessonInlineMark>[];
    }
  }
  return List<LessonInlineMark>.unmodifiable(first);
}

bool _sameMarkTypes(List<LessonInlineMark> left, List<LessonInlineMark> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index].type != right[index].type) return false;
  }
  return true;
}

String _plainText(List<LessonTextRun> children) {
  return children.map((child) => child.text).join();
}
