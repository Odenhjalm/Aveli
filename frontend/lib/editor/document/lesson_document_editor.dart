import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'lesson_document.dart';

class LessonDocumentEditor extends StatefulWidget {
  const LessonDocumentEditor({
    super.key,
    required this.document,
    required this.onChanged,
    this.enabled = true,
    this.minHeight = 280,
  });

  final LessonDocument document;
  final ValueChanged<LessonDocument> onChanged;
  final bool enabled;
  final double minHeight;

  @override
  State<LessonDocumentEditor> createState() => _LessonDocumentEditorState();
}

class _LessonDocumentEditorState extends State<LessonDocumentEditor> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
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
        _syncControllerText(key, _plainText(children));
      } else if (block case LessonHeadingBlock(:final children)) {
        final key = _EditorTarget.block(blockIndex).key;
        liveKeys.add(key);
        _syncControllerText(key, _plainText(children));
      } else if (block case LessonListBlock(:final items)) {
        for (var itemIndex = 0; itemIndex < items.length; itemIndex += 1) {
          final key = _EditorTarget.listItem(blockIndex, itemIndex).key;
          liveKeys.add(key);
          _syncControllerText(key, _plainText(items[itemIndex].children));
        }
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

  void _syncControllerText(String key, String text) {
    final controller = _controllers[key];
    if (controller == null) return;
    final focusNode = _focusNodes[key];
    if (controller.text == text || (focusNode?.hasFocus ?? false)) {
      return;
    }
    controller.text = text;
  }

  TextEditingController _controllerFor(String key, String text) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: text),
    );
  }

  FocusNode _focusNodeFor(String key, _EditorTarget target) {
    return _focusNodes.putIfAbsent(key, () {
      final node = FocusNode();
      node.addListener(() {
        if (node.hasFocus && mounted) {
          setState(() => _selectedTarget = target);
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
    final target = _selectedTarget.normalized(widget.document);
    if (target == null) return;
    final children = _childrenForTarget(target);
    final length = _plainText(children).length;
    if (length == 0) {
      _replaceTargetChildren(target, <LessonTextRun>[
        LessonTextRun('', marks: <LessonInlineMark>[mark]),
      ]);
      return;
    }
    _emit(
      target.itemIndex == null
          ? widget.document.formatBlockInlineRange(
              target.blockIndex,
              start: 0,
              end: length,
              mark: mark,
            )
          : widget.document.formatListItemInlineRange(
              target.blockIndex,
              itemIndex: target.itemIndex!,
              start: 0,
              end: length,
              mark: mark,
            ),
    );
  }

  void _clearFormatting() {
    final target = _selectedTarget.normalized(widget.document);
    if (target == null) return;
    final children = _childrenForTarget(target);
    final length = _plainText(children).length;
    if (length == 0) {
      _replaceTargetChildren(target, const <LessonTextRun>[LessonTextRun('')]);
      return;
    }
    _emit(
      target.itemIndex == null
          ? widget.document.clearBlockInlineFormatting(
              target.blockIndex,
              start: 0,
              end: length,
            )
          : widget.document.clearListItemInlineFormatting(
              target.blockIndex,
              itemIndex: target.itemIndex!,
              start: 0,
              end: length,
            ),
    );
  }

  void _replaceTargetChildren(
    _EditorTarget target,
    List<LessonTextRun> children,
  ) {
    final blocks = widget.document.blocks.isEmpty
        ? <LessonBlock>[LessonParagraphBlock(children: children)]
        : widget.document.blocks;
    final nextBlocks = List<LessonBlock>.from(blocks);
    final block = nextBlocks[target.blockIndex];
    if (target.itemIndex case final itemIndex?) {
      if (block is! LessonListBlock) return;
      final nextItems = List<LessonListItem>.from(block.items);
      nextItems[itemIndex] = nextItems[itemIndex].copyWith(children: children);
      nextBlocks[target.blockIndex] = block.copyWith(items: nextItems);
    } else if (block is LessonParagraphBlock) {
      nextBlocks[target.blockIndex] = block.copyWith(children: children);
    } else if (block is LessonHeadingBlock) {
      nextBlocks[target.blockIndex] = block.copyWith(children: children);
    } else {
      return;
    }
    _emit(LessonDocument(blocks: List<LessonBlock>.unmodifiable(nextBlocks)));
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
    final target = _selectedTarget.normalized(widget.document);
    final sourceBlocks = widget.document.blocks.isEmpty
        ? const <LessonBlock>[
            LessonParagraphBlock(children: <LessonTextRun>[LessonTextRun('')]),
          ]
        : widget.document.blocks;
    final normalizedTarget = target ?? const _EditorTarget.block(0);
    final block = sourceBlocks[normalizedTarget.blockIndex];
    final nextBlocks = List<LessonBlock>.from(sourceBlocks);

    switch (conversion) {
      case _BlockConversion.paragraph:
        final replacement = block is LessonListBlock
            ? block.items
                  .map<LessonBlock>(
                    (item) => LessonParagraphBlock(children: item.children),
                  )
                  .toList(growable: false)
            : <LessonBlock>[
                LessonParagraphBlock(
                  children: _childrenForExistingTextBlock(block),
                ),
              ];
        nextBlocks
          ..removeAt(normalizedTarget.blockIndex)
          ..insertAll(normalizedTarget.blockIndex, replacement);
        break;
      case _BlockConversion.heading:
        final replacement = block is LessonListBlock
            ? block.items
                  .map<LessonBlock>(
                    (item) =>
                        LessonHeadingBlock(level: 2, children: item.children),
                  )
                  .toList(growable: false)
            : <LessonBlock>[
                LessonHeadingBlock(
                  level: 2,
                  children: _childrenForExistingTextBlock(block),
                ),
              ];
        nextBlocks
          ..removeAt(normalizedTarget.blockIndex)
          ..insertAll(normalizedTarget.blockIndex, replacement);
        break;
      case _BlockConversion.bulletList:
        nextBlocks[normalizedTarget.blockIndex] = LessonListBlock.bullet(
          items: _itemsForListConversion(block),
        );
        break;
      case _BlockConversion.orderedList:
        nextBlocks[normalizedTarget.blockIndex] = LessonListBlock.ordered(
          items: _itemsForListConversion(block),
        );
        break;
    }
    _emit(LessonDocument(blocks: List<LessonBlock>.unmodifiable(nextBlocks)));
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
    final theme = Theme.of(context);
    final blocks = widget.document.blocks.isEmpty
        ? const <LessonBlock>[
            LessonParagraphBlock(children: <LessonTextRun>[LessonTextRun('')]),
          ]
        : widget.document.blocks;
    return Container(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
        color: Colors.white.withValues(alpha: 0.92),
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
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: blocks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, blockIndex) {
                final block = blocks[blockIndex];
                return _buildBlockEditor(context, block, blockIndex);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Dokumentmodell: lesson_document_v1. Markdown/Quill anvands inte som sparauktoritet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockEditor(
    BuildContext context,
    LessonBlock block,
    int blockIndex,
  ) {
    if (block is LessonParagraphBlock) {
      return _buildTextBlockEditor(
        context,
        target: _EditorTarget.block(blockIndex),
        label: 'Stycke',
        children: block.children,
        icon: Icons.notes_outlined,
      );
    }
    if (block is LessonHeadingBlock) {
      return _buildTextBlockEditor(
        context,
        target: _EditorTarget.block(blockIndex),
        label: 'Rubrik H${block.level}',
        children: block.children,
        icon: Icons.title_rounded,
      );
    }
    if (block is LessonListBlock) {
      final ordered = block.type == 'ordered_list';
      return Card(
        elevation: 0,
        color: Colors.black.withValues(alpha: 0.03),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    ordered
                        ? Icons.format_list_numbered_rounded
                        : Icons.format_list_bulleted_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(ordered ? 'Numrerad lista' : 'Punktlista'),
                ],
              ),
              const SizedBox(height: 8),
              for (
                var itemIndex = 0;
                itemIndex < block.items.length;
                itemIndex += 1
              )
                _buildTextField(
                  context,
                  target: _EditorTarget.listItem(blockIndex, itemIndex),
                  label: ordered ? '${itemIndex + 1}.' : 'Punkt',
                  children: block.items[itemIndex].children,
                  icon: ordered
                      ? Icons.looks_one_outlined
                      : Icons.circle_outlined,
                ),
            ],
          ),
        ),
      );
    }
    if (block is LessonMediaBlock) {
      return ListTile(
        key: ValueKey<String>('lesson_document_media_$blockIndex'),
        leading: const Icon(Icons.perm_media_outlined),
        title: Text('Media: ${block.mediaType}'),
        subtitle: Text(block.lessonMediaId),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: Colors.black.withValues(alpha: 0.03),
      );
    }
    if (block is LessonCtaBlock) {
      return Card(
        elevation: 0,
        color: Colors.black.withValues(alpha: 0.03),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                key: ValueKey<String>('lesson_document_cta_label_$blockIndex'),
                enabled: widget.enabled,
                controller: _controllerFor(
                  'cta_label_$blockIndex',
                  block.label,
                ),
                decoration: const InputDecoration(labelText: 'CTA text'),
                onChanged: (value) => _updateCtaBlock(blockIndex, label: value),
              ),
              TextField(
                key: ValueKey<String>('lesson_document_cta_url_$blockIndex'),
                enabled: widget.enabled,
                controller: _controllerFor(
                  'cta_url_$blockIndex',
                  block.targetUrl,
                ),
                decoration: const InputDecoration(labelText: 'CTA URL'),
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

  Widget _buildTextBlockEditor(
    BuildContext context, {
    required _EditorTarget target,
    required String label,
    required List<LessonTextRun> children,
    required IconData icon,
  }) {
    return Card(
      elevation: 0,
      color: Colors.black.withValues(alpha: 0.03),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _buildTextField(
          context,
          target: target,
          label: label,
          children: children,
          icon: icon,
        ),
      ),
    );
  }

  Widget _buildTextField(
    BuildContext context, {
    required _EditorTarget target,
    required String label,
    required List<LessonTextRun> children,
    required IconData icon,
  }) {
    final key = target.key;
    final controller = _controllerFor(key, _plainText(children));
    final focusNode = _focusNodeFor(key, target);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: ValueKey<String>('lesson_document_editor_$key'),
          enabled: widget.enabled,
          controller: controller,
          focusNode: focusNode,
          minLines: 1,
          maxLines: null,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            border: const OutlineInputBorder(),
          ),
          onTap: () => _select(target),
          onChanged: (value) => _replaceTargetText(target, value),
        ),
        const SizedBox(height: 8),
        Text('Formatvisning', style: theme.textTheme.labelSmall),
        const SizedBox(height: 4),
        _InlineRunsView(children: children),
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

class LessonDocumentPreview extends StatelessWidget {
  const LessonDocumentPreview({
    super.key,
    required this.document,
    this.media = const <LessonDocumentPreviewMedia>[],
    this.mediaBuilder,
    this.onLaunchUrl,
  });

  final LessonDocument document;
  final List<LessonDocumentPreviewMedia> media;
  final LessonDocumentPreviewMediaBuilder? mediaBuilder;
  final ValueChanged<String>? onLaunchUrl;

  @override
  Widget build(BuildContext context) {
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
    final title = typeMatches
        ? 'Media: ${block.mediaType}'
        : 'Media saknas: ${block.mediaType}';
    final label = resolved?.label?.trim();
    final state = resolved?.state.trim();
    final resolvedUrl = resolved?.resolvedUrl?.trim();
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
            subtitle: Text(
              [
                if (label != null && label.isNotEmpty) label,
                block.lessonMediaId,
                if (state != null && state.isNotEmpty) 'Status: $state',
              ].join('\n'),
            ),
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

  @override
  bool operator ==(Object other) {
    return other is _EditorTarget &&
        other.blockIndex == blockIndex &&
        other.itemIndex == itemIndex;
  }

  @override
  int get hashCode => Object.hash(blockIndex, itemIndex);
}

List<LessonTextRun> _childrenForExistingTextBlock(LessonBlock block) {
  if (block is LessonParagraphBlock) return block.children;
  if (block is LessonHeadingBlock) return block.children;
  return const <LessonTextRun>[LessonTextRun('')];
}

List<LessonListItem> _itemsForListConversion(LessonBlock block) {
  if (block is LessonListBlock) return block.items;
  return <LessonListItem>[
    LessonListItem(children: _childrenForExistingTextBlock(block)),
  ];
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
