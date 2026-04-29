import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lesson_document.dart';
import 'lesson_document_renderer.dart';
import 'lesson_document_selection_splitter.dart';

class LessonEditorSaveSnapshot {
  const LessonEditorSaveSnapshot({
    required this.lessonId,
    required this.sessionId,
    required this.revision,
    required this.document,
  });

  final String lessonId;
  final String sessionId;
  final int revision;
  final LessonDocument document;
}

enum LessonEditorCommandFailure {
  collapsedSelection,
  invalidSelection,
  invalidRange,
  textMismatch,
  unsupportedTarget,
  orderedListDeferred,
  staleSelection,
  identityRegistryMismatch,
  emptyTarget,
}

final class LessonEditorCommandResult {
  const LessonEditorCommandResult.applied() : failure = null;

  const LessonEditorCommandResult.failed(this.failure);

  final LessonEditorCommandFailure? failure;

  bool get applied => failure == null;
}

class LessonDocumentEditorController extends ChangeNotifier {
  _LessonDocumentEditorState? _state;
  LessonEditorCommandResult? _lastCommandResult;

  LessonEditorSaveSnapshot snapshotForSave() {
    final state = _requireAttachedState();
    return state._snapshotForSave();
  }

  LessonDocument? get currentDocument => _state?._document;

  LessonDocument? get baseSavedDocument => _state?._baseSavedDocument;

  bool get dirty => _state?._dirty ?? false;

  int? get savedRevision => _state?._savedRevision;

  int? get currentInsertionIndex => _state?._currentInsertionIndex();

  LessonEditorCommandResult? get lastCommandResult => _lastCommandResult;

  bool acknowledgeSave({
    required LessonEditorSaveSnapshot snapshot,
    required LessonDocument document,
  }) {
    return _state?._acknowledgeSave(snapshot: snapshot, document: document) ??
        false;
  }

  void resetTo({required LessonDocument document, required String lessonId}) {
    _state?._startNewSession(document: document, lessonId: lessonId);
  }

  bool insertMediaBlock({
    required String mediaType,
    required String lessonMediaId,
  }) {
    return _state?._insertMediaBlockFromController(
          mediaType: mediaType,
          lessonMediaId: lessonMediaId,
        ) ??
        false;
  }

  bool insertCta({required String label, required String targetUrl}) {
    return _state?._insertCtaFromController(
          label: label,
          targetUrl: targetUrl,
        ) ??
        false;
  }

  bool replaceMediaReference({
    required String fromLessonMediaId,
    required String toLessonMediaId,
    required String mediaType,
  }) {
    return _state?._replaceMediaReferenceFromController(
          fromLessonMediaId: fromLessonMediaId,
          toLessonMediaId: toLessonMediaId,
          mediaType: mediaType,
        ) ??
        false;
  }

  _LessonDocumentEditorState _requireAttachedState() {
    final state = _state;
    if (state == null) {
      throw StateError('LessonDocumentEditorController is not attached.');
    }
    return state;
  }

  void _attach(_LessonDocumentEditorState state) {
    _state = state;
  }

  void _detach(_LessonDocumentEditorState state) {
    if (_state == state) {
      _state = null;
    }
  }

  void _recordCommandResult(LessonEditorCommandResult result) {
    _lastCommandResult = result;
    notifyListeners();
  }
}

class LessonEditorSessionHost extends StatelessWidget {
  const LessonEditorSessionHost({
    super.key,
    required this.lessonId,
    required this.document,
    required this.controller,
    this.rehydrationKey,
    this.onDirtyChanged,
    this.media = const <LessonDocumentPreviewMedia>[],
    this.onInsertionIndexChanged,
    this.onCommandResult,
    this.enabled = true,
    this.minHeight = 280,
  });

  final String lessonId;
  final LessonDocument document;
  final LessonDocumentEditorController controller;
  final Object? rehydrationKey;
  final ValueChanged<bool>? onDirtyChanged;
  final List<LessonDocumentPreviewMedia> media;
  final ValueChanged<int>? onInsertionIndexChanged;
  final ValueChanged<LessonEditorCommandResult>? onCommandResult;
  final bool enabled;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return LessonDocumentEditor(
      lessonId: lessonId,
      document: document,
      controller: controller,
      rehydrationKey: rehydrationKey,
      onDirtyChanged: onDirtyChanged,
      media: media,
      onInsertionIndexChanged: onInsertionIndexChanged,
      onCommandResult: onCommandResult,
      enabled: enabled,
      minHeight: minHeight,
    );
  }
}

class LessonDocumentEditor extends StatefulWidget {
  const LessonDocumentEditor({
    super.key,
    required this.document,
    this.onChanged,
    this.controller,
    this.lessonId = '',
    this.rehydrationKey,
    this.onDirtyChanged,
    this.media = const <LessonDocumentPreviewMedia>[],
    this.onInsertionIndexChanged,
    this.onCommandResult,
    this.enabled = true,
    this.minHeight = 280,
  });

  final LessonDocument document;
  final ValueChanged<LessonDocument>? onChanged;
  final LessonDocumentEditorController? controller;
  final String lessonId;
  final Object? rehydrationKey;
  final ValueChanged<bool>? onDirtyChanged;
  final List<LessonDocumentPreviewMedia> media;
  final ValueChanged<int>? onInsertionIndexChanged;
  final ValueChanged<LessonEditorCommandResult>? onCommandResult;
  final bool enabled;
  final double minHeight;

  @override
  State<LessonDocumentEditor> createState() => _LessonDocumentEditorState();
}

class _LessonDocumentEditorState extends State<LessonDocumentEditor> {
  static const int _defaultHeadingLevel = 2;
  static int _nextSessionIndex = 0;

  final Map<_EditorControlKey, _LessonTextEditingController> _controllers =
      <_EditorControlKey, _LessonTextEditingController>{};
  final Map<_EditorControlKey, FocusNode> _focusNodes =
      <_EditorControlKey, FocusNode>{};
  final Map<_EditorControlKey, _EditorTarget> _focusTargets =
      <_EditorControlKey, _EditorTarget>{};
  final TextEditingController _emptyDocumentController =
      TextEditingController();
  final FocusNode _emptyDocumentFocusNode = FocusNode();
  _EditorTarget? _selectedTarget;
  int _selectedTargetRevision = 0;
  late LessonDocument _document;
  late _EditorIdentityRegistry _identityRegistry;
  late LessonDocument _baseSavedDocument;
  late String _sessionLessonId;
  late String _sessionId;
  int _revision = 0;
  int _savedRevision = 0;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _document = widget.document;
    _identityRegistry = _EditorIdentityRegistry.fromDocument(_document);
    _selectedTarget = _firstTargetForDocument();
    _selectedTargetRevision = _revision;
    _baseSavedDocument = widget.document;
    _sessionLessonId = widget.lessonId;
    _sessionId = _newSessionId(widget.lessonId);
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(LessonDocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (oldWidget.lessonId != widget.lessonId ||
        oldWidget.rehydrationKey != widget.rehydrationKey) {
      _startNewSession(
        document: widget.document,
        lessonId: widget.lessonId,
        notifyDirty: false,
      );
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    _emptyDocumentController.dispose();
    _emptyDocumentFocusNode.dispose();
    super.dispose();
  }

  static String _newSessionId(String lessonId) {
    final index = _nextSessionIndex;
    _nextSessionIndex += 1;
    return '${lessonId.isEmpty ? 'lesson' : lessonId}:$index';
  }

  void _startNewSession({
    required LessonDocument document,
    required String lessonId,
    bool notifyDirty = true,
  }) {
    final wasDirty = _dirty;
    _document = document;
    _baseSavedDocument = document;
    _sessionLessonId = lessonId;
    _sessionId = _newSessionId(lessonId);
    _revision = 0;
    _savedRevision = 0;
    _dirty = false;
    _identityRegistry = _EditorIdentityRegistry.fromDocument(document);
    _selectedTarget = _firstTargetForDocument();
    _selectedTargetRevision = _revision;
    _emptyDocumentController.clear();
    _syncControllersFromDocument();
    if (notifyDirty && wasDirty) {
      widget.onDirtyChanged?.call(false);
    }
  }

  void _syncControllersFromDocument() {
    final liveKeys = _liveControlKeys(syncText: true);
    if (liveKeys == null) return;
    _disposeStaleControlKeys(liveKeys);
  }

  void _pruneControllers() {
    final liveKeys = _liveControlKeys();
    if (liveKeys == null) return;
    _disposeStaleControlKeys(liveKeys);
  }

  Set<_EditorControlKey>? _liveControlKeys({bool syncText = false}) {
    if (_identityRegistry.blocks.length != _document.blocks.length) {
      return null;
    }
    final liveKeys = <_EditorControlKey>{};
    final blocks = _document.blocks;
    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex += 1) {
      final block = blocks[blockIndex];
      final identity = _identityRegistry.blocks[blockIndex];
      if (block case LessonParagraphBlock(:final children)) {
        final key = _nodeControlKey(identity.blockId);
        liveKeys.add(key);
        if (syncText) {
          _syncControllerText(key, _plainText(children), children);
        }
      } else if (block case LessonHeadingBlock(:final children)) {
        final key = _nodeControlKey(identity.blockId);
        liveKeys.add(key);
        if (syncText) {
          _syncControllerText(key, _plainText(children), children);
        }
      } else if (block case LessonListBlock(:final items)) {
        if (identity.listItemIds.length != items.length) return null;
        for (var itemIndex = 0; itemIndex < items.length; itemIndex += 1) {
          final key = _nodeControlKey(identity.listItemIds[itemIndex]);
          liveKeys.add(key);
          if (syncText) {
            _syncControllerText(
              key,
              _plainText(items[itemIndex].children),
              items[itemIndex].children,
            );
          }
        }
      } else if (block case LessonCtaBlock(:final label, :final targetUrl)) {
        final labelKey = _ctaControlKey(identity.blockId, _CtaField.label);
        final urlKey = _ctaControlKey(identity.blockId, _CtaField.url);
        liveKeys.add(labelKey);
        liveKeys.add(urlKey);
        if (syncText) {
          _syncControllerText(labelKey, label);
          _syncControllerText(urlKey, targetUrl);
        }
      }
    }
    return liveKeys;
  }

  void _disposeStaleControlKeys(Set<_EditorControlKey> liveKeys) {
    final staleKeys = _controllers.keys
        .where((key) => !liveKeys.contains(key))
        .toList(growable: false);
    for (final key in staleKeys) {
      _disposeControlKey(key);
    }
  }

  void _disposeControlKey(_EditorControlKey key) {
    _controllers.remove(key)?.dispose();
    _focusNodes.remove(key)?.dispose();
    _focusTargets.remove(key);
  }

  void _disposeRemovedIdentityKeys(
    Iterable<_BlockIdentity> removedIdentities,
    Iterable<_BlockIdentity> retainedIdentities,
  ) {
    final retainedKeys = <_EditorControlKey>{
      for (final identity in retainedIdentities) ..._controlKeysFor(identity),
    };
    for (final identity in removedIdentities) {
      for (final key in _controlKeysFor(identity)) {
        if (!retainedKeys.contains(key)) {
          _disposeControlKey(key);
        }
      }
    }
  }

  Iterable<_EditorControlKey> _controlKeysFor(_BlockIdentity identity) sync* {
    yield _nodeControlKey(identity.blockId);
    for (final itemId in identity.listItemIds) {
      yield _nodeControlKey(itemId);
    }
    yield _ctaControlKey(identity.blockId, _CtaField.label);
    yield _ctaControlKey(identity.blockId, _CtaField.url);
  }

  void _syncControllerText(
    _EditorControlKey key,
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
    _EditorControlKey key,
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

  FocusNode _focusNodeFor(_EditorControlKey key, _EditorTarget target) {
    _focusTargets[key] = target;
    return _focusNodes.putIfAbsent(key, () {
      final node = FocusNode();
      node.addListener(() {
        if (node.hasFocus && mounted) {
          final currentTarget = _focusTargets[key];
          if (currentTarget != null) {
            _select(currentTarget);
          }
        }
      });
      return node;
    });
  }

  _EditorControlKey _nodeControlKey(_EditorNodeId nodeId) {
    return _EditorControlKey.node(nodeId);
  }

  _EditorControlKey _ctaControlKey(_EditorNodeId blockId, _CtaField field) {
    return _EditorControlKey.cta(blockId, field);
  }

  _EditorControlKey? _controlKeyForTarget(_EditorTarget target) {
    return switch (target) {
      _BlockTextTarget(:final blockId) => _nodeControlKey(blockId),
      _ListItemTextTarget(:final itemId) => _nodeControlKey(itemId),
      _CtaFieldTarget(:final blockId, :final field) => _ctaControlKey(
        blockId,
        field,
      ),
      _BlockTarget() => null,
    };
  }

  _BlockIdentity? _identityAtBlockIndex(int blockIndex) {
    if (_identityRegistry.blocks.length != _document.blocks.length) {
      return null;
    }
    if (blockIndex < 0 || blockIndex >= _identityRegistry.blocks.length) {
      return null;
    }
    return _identityRegistry.blocks[blockIndex];
  }

  int? _blockIndexFor(_EditorNodeId blockId) {
    if (_identityRegistry.blocks.length != _document.blocks.length) {
      return null;
    }
    for (
      var blockIndex = 0;
      blockIndex < _identityRegistry.blocks.length;
      blockIndex += 1
    ) {
      if (_identityRegistry.blocks[blockIndex].blockId == blockId) {
        return blockIndex;
      }
    }
    return null;
  }

  _ListItemLocation? _listItemLocationFor(_EditorNodeId itemId) {
    if (_identityRegistry.blocks.length != _document.blocks.length) {
      return null;
    }
    for (
      var blockIndex = 0;
      blockIndex < _identityRegistry.blocks.length;
      blockIndex += 1
    ) {
      final identity = _identityRegistry.blocks[blockIndex];
      final block = _document.blocks[blockIndex];
      if (block is! LessonListBlock ||
          identity.listItemIds.length != block.items.length) {
        continue;
      }
      for (
        var itemIndex = 0;
        itemIndex < identity.listItemIds.length;
        itemIndex += 1
      ) {
        if (identity.listItemIds[itemIndex] == itemId) {
          return _ListItemLocation(
            blockIndex: blockIndex,
            itemIndex: itemIndex,
            block: block,
            blockIdentity: identity,
          );
        }
      }
    }
    return null;
  }

  int? _insertionIndexForTarget(_EditorTarget target) {
    final blockIndex = switch (target) {
      _BlockTextTarget(:final blockId) ||
      _BlockTarget(:final blockId) ||
      _CtaFieldTarget(:final blockId) => _blockIndexFor(blockId),
      _ListItemTextTarget(:final itemId) => _listItemLocationFor(
        itemId,
      )?.blockIndex,
    };
    if (blockIndex == null) return null;
    return (blockIndex + 1).clamp(0, _document.blocks.length).toInt();
  }

  bool _targetExists(_EditorTarget target) {
    return switch (target) {
      _BlockTextTarget(:final blockId) => switch (_blockIndexFor(blockId)) {
        final blockIndex? =>
          _document.blocks[blockIndex] is LessonParagraphBlock ||
              _document.blocks[blockIndex] is LessonHeadingBlock,
        null => false,
      },
      _ListItemTextTarget(:final itemId) =>
        _listItemLocationFor(itemId) != null,
      _BlockTarget(:final blockId) => _blockIndexFor(blockId) != null,
      _CtaFieldTarget(:final blockId) => switch (_blockIndexFor(blockId)) {
        final blockIndex? => _document.blocks[blockIndex] is LessonCtaBlock,
        null => false,
      },
    };
  }

  _EditorNodeId? _owningBlockIdForTarget(_EditorTarget target) {
    return switch (target) {
      _BlockTextTarget(:final blockId) ||
      _BlockTarget(:final blockId) ||
      _CtaFieldTarget(:final blockId) => blockId,
      _ListItemTextTarget(:final itemId) => _listItemLocationFor(
        itemId,
      )?.blockIdentity.blockId,
    };
  }

  bool _targetBelongsToIdentity(
    _EditorTarget? target,
    _BlockIdentity identity,
  ) {
    if (target == null) return false;
    return switch (target) {
      _BlockTextTarget(:final blockId) ||
      _BlockTarget(:final blockId) ||
      _CtaFieldTarget(:final blockId) => blockId == identity.blockId,
      _ListItemTextTarget(:final itemId) => identity.listItemIds.contains(
        itemId,
      ),
    };
  }

  _EditorTarget? _firstTargetForDocument() {
    for (var index = 0; index < _document.blocks.length; index += 1) {
      final target = _targetForBlockIndex(index);
      if (target != null) return target;
    }
    return null;
  }

  _EditorTarget? _targetForBlockIndex(int blockIndex) {
    final identity = _identityAtBlockIndex(blockIndex);
    if (identity == null || blockIndex >= _document.blocks.length) {
      return null;
    }
    return _targetForBlock(_document.blocks[blockIndex], identity);
  }

  _EditorTarget? _targetForBlock(LessonBlock block, _BlockIdentity identity) {
    if (block is LessonParagraphBlock || block is LessonHeadingBlock) {
      return _BlockTextTarget(identity.blockId);
    }
    if (block is LessonListBlock) {
      if (identity.listItemIds.length != block.items.length ||
          identity.listItemIds.isEmpty) {
        return null;
      }
      return _ListItemTextTarget(identity.listItemIds.first);
    }
    if (block is LessonCtaBlock) {
      return _CtaFieldTarget(identity.blockId, _CtaField.label);
    }
    return _BlockTarget(identity.blockId);
  }

  bool _identityRegistryMatchesDocument() {
    if (_identityRegistry.blocks.length != _document.blocks.length) {
      return false;
    }
    for (
      var blockIndex = 0;
      blockIndex < _document.blocks.length;
      blockIndex += 1
    ) {
      final block = _document.blocks[blockIndex];
      final identity = _identityRegistry.blocks[blockIndex];
      if (block is LessonListBlock &&
          identity.listItemIds.length != block.items.length) {
        return false;
      }
    }
    return true;
  }

  LessonEditorCommandResult _recordCommandFailure(
    LessonEditorCommandFailure failure,
  ) {
    final result = LessonEditorCommandResult.failed(failure);
    _recordCommandResult(result);
    return result;
  }

  LessonEditorCommandResult _recordCommandApplied() {
    const result = LessonEditorCommandResult.applied();
    _recordCommandResult(result);
    return result;
  }

  void _recordCommandResult(LessonEditorCommandResult result) {
    widget.controller?._recordCommandResult(result);
    widget.onCommandResult?.call(result);
  }

  void _setSelectedTargetForCurrentRevision(_EditorTarget? target) {
    setState(() {
      _selectedTarget = target;
      _selectedTargetRevision = _revision;
    });
  }

  void _emit(LessonDocument document) {
    if (!widget.enabled) return;
    _applyDocument(document);
  }

  void _applyDocument(
    LessonDocument document, {
    _EditorIdentityRegistry? identityRegistry,
  }) {
    final wasDirty = _dirty;
    setState(() {
      _document = document;
      if (identityRegistry != null) {
        _identityRegistry = identityRegistry;
      }
      _revision += 1;
      _dirty = true;
    });
    _pruneControllers();
    if (!wasDirty) {
      widget.onDirtyChanged?.call(true);
    }
    widget.onChanged?.call(document);
  }

  LessonEditorSaveSnapshot _snapshotForSave() {
    return LessonEditorSaveSnapshot(
      lessonId: _sessionLessonId,
      sessionId: _sessionId,
      revision: _revision,
      document: _document,
    );
  }

  bool _acknowledgeSave({
    required LessonEditorSaveSnapshot snapshot,
    required LessonDocument document,
  }) {
    if (snapshot.lessonId != _sessionLessonId ||
        snapshot.sessionId != _sessionId ||
        snapshot.revision > _revision) {
      return false;
    }
    final hasInterveningEdits = snapshot.revision != _revision;
    final wasDirty = _dirty;
    if (hasInterveningEdits) {
      setState(() {
        _baseSavedDocument = document;
        _savedRevision = snapshot.revision;
        _dirty = true;
      });
      return true;
    }
    setState(() {
      _document = document;
      _baseSavedDocument = document;
      _savedRevision = _revision;
      _dirty = false;
    });
    _syncControllersFromDocument();
    if (wasDirty) {
      widget.onDirtyChanged?.call(false);
    }
    widget.onChanged?.call(document);
    return true;
  }

  int _currentInsertionIndex() {
    final target = _selectedTarget;
    if (target == null) return _document.blocks.length;
    return _insertionIndexForTarget(target) ?? _document.blocks.length;
  }

  bool _insertMediaBlockFromController({
    required String mediaType,
    required String lessonMediaId,
  }) {
    if (!widget.enabled) return false;
    const insertionIndex = 0;
    final block = LessonMediaBlock(
      mediaType: mediaType,
      lessonMediaId: lessonMediaId,
    );
    final next = _document.insertBlock(insertionIndex, block);
    final nextRegistry = _identityRegistry.copy();
    final identity = nextRegistry.createBlockIdentity(block);
    nextRegistry.blocks.insert(insertionIndex, identity);
    _applyDocument(next, identityRegistry: nextRegistry);
    final nextTarget = _BlockTarget(identity.blockId);
    widget.onInsertionIndexChanged?.call(
      _insertionIndexForTarget(nextTarget) ?? insertionIndex + 1,
    );
    _setSelectedTargetForCurrentRevision(nextTarget);
    return true;
  }

  bool _insertCtaFromController({
    required String label,
    required String targetUrl,
  }) {
    if (!widget.enabled) return false;
    final insertionIndex = _currentInsertionIndex();
    final block = LessonCtaBlock(label: label, targetUrl: targetUrl);
    final next = _document.insertBlock(insertionIndex, block);
    final nextRegistry = _identityRegistry.copy();
    final identity = nextRegistry.createBlockIdentity(block);
    nextRegistry.blocks.insert(insertionIndex, identity);
    _applyDocument(next, identityRegistry: nextRegistry);
    final nextTarget = _CtaFieldTarget(identity.blockId, _CtaField.label);
    widget.onInsertionIndexChanged?.call(
      _insertionIndexForTarget(nextTarget) ?? insertionIndex + 1,
    );
    _setSelectedTargetForCurrentRevision(nextTarget);
    return true;
  }

  bool _replaceMediaReferenceFromController({
    required String fromLessonMediaId,
    required String toLessonMediaId,
    required String mediaType,
  }) {
    if (!widget.enabled) return false;
    if (fromLessonMediaId.isEmpty || toLessonMediaId.isEmpty) return false;
    var changed = false;
    final nextBlocks = <LessonBlock>[];
    for (final block in _document.blocks) {
      if (block is LessonMediaBlock &&
          block.lessonMediaId == fromLessonMediaId) {
        nextBlocks.add(
          LessonMediaBlock(
            id: block.id,
            mediaType: mediaType,
            lessonMediaId: toLessonMediaId,
          ),
        );
        changed = true;
      } else {
        nextBlocks.add(block);
      }
    }
    if (!changed) return false;
    _emit(LessonDocument(blocks: List<LessonBlock>.unmodifiable(nextBlocks)));
    return true;
  }

  void _select(_EditorTarget target) {
    final insertionIndex = _insertionIndexForTarget(target);
    if (insertionIndex == null) return;
    widget.onInsertionIndexChanged?.call(insertionIndex);
    if (_selectedTarget == target && _selectedTargetRevision == _revision) {
      return;
    }
    _setSelectedTargetForCurrentRevision(target);
  }

  void _replaceTargetText(_EditorTarget target, String text) {
    final normalizedText = text.replaceAll('\r\n', '\n');
    final nextBlocks = List<LessonBlock>.from(_document.blocks);
    if (target case _ListItemTextTarget(:final itemId)) {
      final location = _listItemLocationFor(itemId);
      if (location == null) return;
      final block = location.block;
      final nextItems = List<LessonListItem>.from(block.items);
      final item = nextItems[location.itemIndex];
      nextItems[location.itemIndex] = item.copyWith(
        children: _textRunsForReplacement(item.children, normalizedText),
      );
      nextBlocks[location.blockIndex] = block.copyWith(items: nextItems);
    } else if (target case _BlockTextTarget(:final blockId)) {
      final blockIndex = _blockIndexFor(blockId);
      if (blockIndex == null) return;
      final block = nextBlocks[blockIndex];
      if (block is LessonParagraphBlock) {
        nextBlocks[blockIndex] = block.copyWith(
          children: _textRunsForReplacement(block.children, normalizedText),
        );
      } else if (block is LessonHeadingBlock) {
        nextBlocks[blockIndex] = block.copyWith(
          children: _textRunsForReplacement(block.children, normalizedText),
        );
      } else {
        return;
      }
    } else {
      return;
    }
    _emit(LessonDocument(blocks: List<LessonBlock>.unmodifiable(nextBlocks)));
  }

  void _applyInlineMark(LessonInlineMark mark) {
    final selection = _selectedTextRange();
    if (selection == null) return;
    final target = selection.target;
    if (target case _BlockTextTarget(:final blockId)) {
      final blockIndex = _blockIndexFor(blockId);
      if (blockIndex == null) return;
      _emit(
        _document.toggleBlockInlineMark(
          blockIndex,
          start: selection.start,
          end: selection.end,
          mark: mark,
        ),
      );
    } else if (target case _ListItemTextTarget(:final itemId)) {
      final location = _listItemLocationFor(itemId);
      if (location == null) return;
      _emit(
        _document.toggleListItemInlineMark(
          location.blockIndex,
          itemIndex: location.itemIndex,
          start: selection.start,
          end: selection.end,
          mark: mark,
        ),
      );
    }
  }

  void _clearFormatting() {
    final selection = _selectedTextRange();
    if (selection == null) return;
    final target = selection.target;
    if (target case _BlockTextTarget(:final blockId)) {
      final blockIndex = _blockIndexFor(blockId);
      if (blockIndex == null) return;
      _emit(
        _document.clearBlockInlineFormatting(
          blockIndex,
          start: selection.start,
          end: selection.end,
        ),
      );
    } else if (target case _ListItemTextTarget(:final itemId)) {
      final location = _listItemLocationFor(itemId);
      if (location == null) return;
      _emit(
        _document.clearListItemInlineFormatting(
          location.blockIndex,
          itemIndex: location.itemIndex,
          start: selection.start,
          end: selection.end,
        ),
      );
    }
  }

  List<LessonTextRun> _childrenForTarget(_EditorTarget target) {
    if (target case _ListItemTextTarget(:final itemId)) {
      final location = _listItemLocationFor(itemId);
      if (location == null) return const <LessonTextRun>[];
      return location.block.items[location.itemIndex].children;
    }
    if (target case _BlockTextTarget(:final blockId)) {
      final blockIndex = _blockIndexFor(blockId);
      if (blockIndex == null) return const <LessonTextRun>[];
      final block = _document.blocks[blockIndex];
      if (block is LessonParagraphBlock) return block.children;
      if (block is LessonHeadingBlock) return block.children;
    }
    return const <LessonTextRun>[];
  }

  void _convertSelectedBlock(_BlockConversion conversion) {
    final selection = _selectedTextRange();
    if (selection == null) return;
    final sourceBlocks = _document.blocks;
    final target = selection.target;
    final split = _splitRunsByRange(
      _childrenForTarget(target),
      start: selection.start,
      end: selection.end,
    );
    final nextBlocks = List<LessonBlock>.from(sourceBlocks);
    final nextRegistry = _identityRegistry.copy();
    late final int blockIndex;
    late final _BlockIdentity removedIdentity;
    late final List<LessonBlock> replacement;
    late final List<_BlockIdentity> replacementIdentities;
    late final _EditorTarget nextTarget;

    if (target case _ListItemTextTarget(:final itemId)) {
      final location = _listItemLocationFor(itemId);
      if (location == null) return;
      blockIndex = location.blockIndex;
      removedIdentity = location.blockIdentity;
      replacement = _splitListItemSelectionIntoBlocks(
        location.block,
        itemIndex: location.itemIndex,
        split: split,
        conversion: conversion,
      );
      replacementIdentities = _splitListItemSelectionIdentities(
        sourceIdentity: removedIdentity,
        itemIndex: location.itemIndex,
        split: split,
        conversion: conversion,
        replacement: replacement,
        selectedItemId: itemId,
        registry: nextRegistry,
      );
      nextTarget = _targetForConvertedSelection(
        replacement: replacement,
        identities: replacementIdentities,
        selectedNodeId: itemId,
      );
    } else if (target case _BlockTextTarget(:final blockId)) {
      final resolvedBlockIndex = _blockIndexFor(blockId);
      if (resolvedBlockIndex == null) return;
      final identity = _identityAtBlockIndex(resolvedBlockIndex);
      if (identity == null) return;
      final block = sourceBlocks[resolvedBlockIndex];
      if (block is! LessonParagraphBlock && block is! LessonHeadingBlock) {
        return;
      }
      blockIndex = resolvedBlockIndex;
      removedIdentity = identity;
      replacement = _splitTextBlockSelectionIntoBlocks(
        block,
        split: split,
        conversion: conversion,
      );
      replacementIdentities = _splitTextBlockSelectionIdentities(
        split: split,
        conversion: conversion,
        replacement: replacement,
        selectedNodeId: blockId,
        registry: nextRegistry,
      );
      nextTarget = _targetForConvertedSelection(
        replacement: replacement,
        identities: replacementIdentities,
        selectedNodeId: blockId,
      );
    } else {
      return;
    }

    nextBlocks
      ..removeAt(blockIndex)
      ..insertAll(blockIndex, replacement);
    nextRegistry.blocks
      ..removeAt(blockIndex)
      ..insertAll(blockIndex, replacementIdentities);
    _disposeRemovedIdentityKeys([removedIdentity], replacementIdentities);
    final next = LessonDocument(
      blocks: List<LessonBlock>.unmodifiable(nextBlocks),
    );
    _applyDocument(next, identityRegistry: nextRegistry);
    widget.onInsertionIndexChanged?.call(
      _insertionIndexForTarget(nextTarget) ?? blockIndex + 1,
    );
    _setSelectedTargetForCurrentRevision(nextTarget);
  }

  void _convertSelectedHeading() {
    final selectionResult = _resolveSelectedTextRange();
    final selection = selectionResult.range;
    if (selection == null) {
      _recordCommandFailure(
        selectionResult.failure ?? LessonEditorCommandFailure.invalidSelection,
      );
      return;
    }
    if (selection.revision != _revision) {
      _recordCommandFailure(LessonEditorCommandFailure.staleSelection);
      return;
    }

    late final int blockIndex;
    late final _BlockIdentity sourceIdentity;
    late final LessonSelectionSplitTarget splitTarget;

    if (selection.target case _BlockTextTarget(:final blockId)) {
      final resolvedBlockIndex = _blockIndexFor(blockId);
      if (resolvedBlockIndex == null) {
        _recordCommandFailure(_headingResolutionFailure());
        return;
      }
      final identity = _identityAtBlockIndex(resolvedBlockIndex);
      if (identity == null) {
        _recordCommandFailure(_headingResolutionFailure());
        return;
      }
      blockIndex = resolvedBlockIndex;
      sourceIdentity = identity;
      splitTarget = LessonTextBlockSelectionTarget(blockIndex: blockIndex);
    } else if (selection.target case _ListItemTextTarget(:final itemId)) {
      final location = _listItemLocationFor(itemId);
      if (location == null) {
        _recordCommandFailure(_headingResolutionFailure());
        return;
      }
      blockIndex = location.blockIndex;
      sourceIdentity = location.blockIdentity;
      splitTarget = LessonListItemSelectionTarget(
        blockIndex: blockIndex,
        itemIndex: location.itemIndex,
      );
    } else {
      _recordCommandFailure(LessonEditorCommandFailure.unsupportedTarget);
      return;
    }

    final result = splitLessonDocumentSelection(
      document: _document,
      target: splitTarget,
      start: selection.start,
      end: selection.end,
      conversion: const LessonSelectionHeadingConversion(
        level: _defaultHeadingLevel,
      ),
    );
    final metadata = result.metadata;
    if (!result.applied || metadata == null) {
      _recordCommandFailure(_failureForSplitStatus(result.status));
      return;
    }

    final replacement = result.document.blocks
        .skip(blockIndex)
        .take(metadata.replacementCount)
        .toList(growable: false);
    final nextRegistry = _identityRegistry.copy();
    final replacementIdentities = _identityRemapForSplit(
      metadata: metadata,
      replacement: replacement,
      sourceIdentity: sourceIdentity,
      registry: nextRegistry,
    );
    if (replacementIdentities == null) {
      _recordCommandFailure(
        LessonEditorCommandFailure.identityRegistryMismatch,
      );
      return;
    }

    nextRegistry.blocks
      ..removeAt(blockIndex)
      ..insertAll(blockIndex, replacementIdentities);
    _disposeRemovedIdentityKeys([sourceIdentity], replacementIdentities);
    final nextTarget = _targetForSplitSelection(
      metadata: metadata,
      replacementIdentities: replacementIdentities,
    );
    if (nextTarget == null) {
      _recordCommandFailure(
        LessonEditorCommandFailure.identityRegistryMismatch,
      );
      return;
    }

    _applyDocument(result.document, identityRegistry: nextRegistry);
    widget.onInsertionIndexChanged?.call(
      _insertionIndexForTarget(nextTarget) ?? blockIndex + 1,
    );
    _setSelectedTargetForCurrentRevision(nextTarget);
    _recordCommandApplied();
  }

  LessonEditorCommandFailure _headingResolutionFailure() {
    return _identityRegistryMatchesDocument()
        ? LessonEditorCommandFailure.staleSelection
        : LessonEditorCommandFailure.identityRegistryMismatch;
  }

  LessonEditorCommandFailure _failureForSplitStatus(
    LessonSelectionSplitStatus status,
  ) {
    return switch (status) {
      LessonSelectionSplitStatus.applied =>
        LessonEditorCommandFailure.invalidSelection,
      LessonSelectionSplitStatus.collapsedSelection =>
        LessonEditorCommandFailure.collapsedSelection,
      LessonSelectionSplitStatus.invalidRange =>
        LessonEditorCommandFailure.invalidRange,
      LessonSelectionSplitStatus.unsupportedTarget =>
        LessonEditorCommandFailure.unsupportedTarget,
      LessonSelectionSplitStatus.orderedListDeferred =>
        LessonEditorCommandFailure.orderedListDeferred,
    };
  }

  List<_BlockIdentity>? _identityRemapForSplit({
    required LessonSelectionSplitMetadata metadata,
    required List<LessonBlock> replacement,
    required _BlockIdentity sourceIdentity,
    required _EditorIdentityRegistry registry,
  }) {
    if (replacement.length != metadata.identityRemapHints.length) return null;
    final identities = <_BlockIdentity>[];
    for (var index = 0; index < replacement.length; index += 1) {
      final hint = metadata.identityRemapHints[index];
      if (hint.replacementIndex != index) return null;
      final identity = _identityForSplitHint(
        block: replacement[index],
        hint: hint,
        sourceIdentity: sourceIdentity,
        registry: registry,
      );
      if (identity == null) return null;
      identities.add(identity);
    }
    return identities;
  }

  _BlockIdentity? _identityForSplitHint({
    required LessonBlock block,
    required LessonSelectionSplitReplacementIdentityHint hint,
    required _BlockIdentity sourceIdentity,
    required _EditorIdentityRegistry registry,
  }) {
    final blockId = _nodeIdForSplitAction(
      hint.blockIdentityAction,
      sourceIdentity: sourceIdentity,
      sourceListItemIndex: hint.sourceListItemIndex,
      registry: registry,
    );
    if (blockId == null) return null;
    if (block is! LessonListBlock) {
      return _BlockIdentity(blockId: blockId);
    }
    if (hint.listItemIdentityHints.length != block.items.length) return null;
    final itemIds = <_EditorNodeId>[];
    for (final itemHint in hint.listItemIdentityHints) {
      if (itemHint.itemIndex != itemIds.length) return null;
      final itemId = _nodeIdForSplitAction(
        itemHint.action,
        sourceIdentity: sourceIdentity,
        sourceListItemIndex: itemHint.sourceListItemIndex,
        registry: registry,
      );
      if (itemId == null) return null;
      itemIds.add(itemId);
    }
    return _BlockIdentity(blockId: blockId, listItemIds: itemIds);
  }

  _EditorNodeId? _nodeIdForSplitAction(
    LessonSelectionSplitIdentityAction action, {
    required _BlockIdentity sourceIdentity,
    required int? sourceListItemIndex,
    required _EditorIdentityRegistry registry,
  }) {
    return switch (action) {
      LessonSelectionSplitIdentityAction.createRuntimeIdentity =>
        registry.nextNodeId(),
      LessonSelectionSplitIdentityAction.reuseSourceBlockRuntimeIdentity =>
        sourceIdentity.blockId,
      LessonSelectionSplitIdentityAction.reuseSourceListItemRuntimeIdentity =>
        _sourceListItemNodeId(sourceIdentity, sourceListItemIndex),
    };
  }

  _EditorNodeId? _sourceListItemNodeId(
    _BlockIdentity sourceIdentity,
    int? sourceListItemIndex,
  ) {
    if (sourceListItemIndex == null ||
        sourceListItemIndex < 0 ||
        sourceListItemIndex >= sourceIdentity.listItemIds.length) {
      return null;
    }
    return sourceIdentity.listItemIds[sourceListItemIndex];
  }

  _EditorTarget? _targetForSplitSelection({
    required LessonSelectionSplitMetadata metadata,
    required List<_BlockIdentity> replacementIdentities,
  }) {
    if (metadata.selectedReplacementIndex < 0 ||
        metadata.selectedReplacementIndex >= replacementIdentities.length) {
      return null;
    }
    final identity = replacementIdentities[metadata.selectedReplacementIndex];
    return switch (metadata.selectedOutputTargetType) {
      LessonSelectionSplitOutputTargetType.blockText => _BlockTextTarget(
        identity.blockId,
      ),
      LessonSelectionSplitOutputTargetType.listItemText =>
        identity.listItemIds.isEmpty
            ? null
            : _ListItemTextTarget(identity.listItemIds.first),
    };
  }

  List<_BlockIdentity> _splitTextBlockSelectionIdentities({
    required _RunRangeSplit split,
    required _BlockConversion conversion,
    required List<LessonBlock> replacement,
    required _EditorNodeId selectedNodeId,
    required _EditorIdentityRegistry registry,
  }) {
    final identities = <_BlockIdentity>[];
    var replacementIndex = 0;
    if (_hasText(split.before)) {
      identities.add(
        registry.createBlockIdentity(replacement[replacementIndex]),
      );
      replacementIndex += 1;
    }
    identities.add(
      _identityForConvertedSelectionBlock(
        replacement[replacementIndex],
        selectedNodeId: selectedNodeId,
        registry: registry,
      ),
    );
    replacementIndex += 1;
    if (_hasText(split.after)) {
      identities.add(
        registry.createBlockIdentity(replacement[replacementIndex]),
      );
    }
    return identities;
  }

  List<_BlockIdentity> _splitListItemSelectionIdentities({
    required _BlockIdentity sourceIdentity,
    required int itemIndex,
    required _RunRangeSplit split,
    required _BlockConversion conversion,
    required List<LessonBlock> replacement,
    required _EditorNodeId selectedItemId,
    required _EditorIdentityRegistry registry,
  }) {
    final identities = <_BlockIdentity>[];
    final beforeItemIds = <_EditorNodeId>[
      ...sourceIdentity.listItemIds.take(itemIndex),
      if (_hasText(split.before)) registry.nextNodeId(),
    ];
    final afterItemIds = <_EditorNodeId>[
      if (_hasText(split.after)) registry.nextNodeId(),
      ...sourceIdentity.listItemIds.skip(itemIndex + 1),
    ];
    var replacementIndex = 0;
    if (beforeItemIds.isNotEmpty) {
      identities.add(
        _BlockIdentity(
          blockId: sourceIdentity.blockId,
          listItemIds: beforeItemIds,
        ),
      );
      replacementIndex += 1;
    }
    identities.add(
      _identityForConvertedSelectionBlock(
        replacement[replacementIndex],
        selectedNodeId: selectedItemId,
        registry: registry,
      ),
    );
    replacementIndex += 1;
    if (afterItemIds.isNotEmpty) {
      identities.add(
        _BlockIdentity(
          blockId: beforeItemIds.isEmpty
              ? sourceIdentity.blockId
              : registry.nextNodeId(),
          listItemIds: afterItemIds,
        ),
      );
    }
    return identities;
  }

  _BlockIdentity _identityForConvertedSelectionBlock(
    LessonBlock block, {
    required _EditorNodeId selectedNodeId,
    required _EditorIdentityRegistry registry,
  }) {
    if (block is LessonListBlock) {
      return _BlockIdentity(
        blockId: registry.nextNodeId(),
        listItemIds: [
          selectedNodeId,
          for (var index = 1; index < block.items.length; index += 1)
            registry.nextNodeId(),
        ],
      );
    }
    return _BlockIdentity(blockId: selectedNodeId);
  }

  _EditorTarget _targetForConvertedSelection({
    required List<LessonBlock> replacement,
    required List<_BlockIdentity> identities,
    required _EditorNodeId selectedNodeId,
  }) {
    for (var index = 0; index < identities.length; index += 1) {
      final identity = identities[index];
      final block = replacement[index];
      if (identity.blockId == selectedNodeId &&
          (block is LessonParagraphBlock || block is LessonHeadingBlock)) {
        return _BlockTextTarget(selectedNodeId);
      }
      if (block is LessonListBlock &&
          identity.listItemIds.contains(selectedNodeId)) {
        return _ListItemTextTarget(selectedNodeId);
      }
    }
    return _BlockTextTarget(selectedNodeId);
  }

  void _toggleHeading() {
    final target = _activeTextTarget();
    if (target == null) return;
    final sourceBlocks = _document.blocks;
    final nextBlocks = List<LessonBlock>.from(sourceBlocks);
    final nextRegistry = _identityRegistry.copy();
    late final _EditorTarget nextTarget;

    if (target case _ListItemTextTarget(:final itemId)) {
      final location = _listItemLocationFor(itemId);
      if (location == null) return;
      final replacement = _toggleHeadingForListItem(
        location.block,
        location.itemIndex,
      );
      final replacementIdentities = _toggleHeadingListItemIdentities(
        sourceIdentity: location.blockIdentity,
        itemIndex: location.itemIndex,
        selectedItemId: itemId,
        registry: nextRegistry,
      );
      nextBlocks
        ..removeAt(location.blockIndex)
        ..insertAll(location.blockIndex, replacement);
      nextRegistry.blocks
        ..removeAt(location.blockIndex)
        ..insertAll(location.blockIndex, replacementIdentities);
      _disposeRemovedIdentityKeys([
        location.blockIdentity,
      ], replacementIdentities);
      nextTarget = _BlockTextTarget(itemId);
    } else if (target case _BlockTextTarget(:final blockId)) {
      final blockIndex = _blockIndexFor(blockId);
      if (blockIndex == null) return;
      final block = sourceBlocks[blockIndex];
      if (block is LessonHeadingBlock) {
        nextBlocks[blockIndex] = LessonParagraphBlock(
          id: block.id,
          children: block.children,
        );
        nextTarget = _BlockTextTarget(blockId);
      } else if (block is LessonParagraphBlock) {
        nextBlocks[blockIndex] = LessonHeadingBlock(
          id: block.id,
          level: _defaultHeadingLevel,
          children: block.children,
        );
        nextTarget = _BlockTextTarget(blockId);
      } else {
        return;
      }
    } else {
      return;
    }

    final next = LessonDocument(
      blocks: List<LessonBlock>.unmodifiable(nextBlocks),
    );
    _applyDocument(next, identityRegistry: nextRegistry);
    widget.onInsertionIndexChanged?.call(
      _insertionIndexForTarget(nextTarget) ?? _currentInsertionIndex(),
    );
    _setSelectedTargetForCurrentRevision(nextTarget);
  }

  List<_BlockIdentity> _toggleHeadingListItemIdentities({
    required _BlockIdentity sourceIdentity,
    required int itemIndex,
    required _EditorNodeId selectedItemId,
    required _EditorIdentityRegistry registry,
  }) {
    final identities = <_BlockIdentity>[];
    final beforeItemIds = sourceIdentity.listItemIds
        .take(itemIndex)
        .toList(growable: false);
    final afterItemIds = sourceIdentity.listItemIds
        .skip(itemIndex + 1)
        .toList(growable: false);
    if (beforeItemIds.isNotEmpty) {
      identities.add(
        _BlockIdentity(
          blockId: sourceIdentity.blockId,
          listItemIds: beforeItemIds,
        ),
      );
    }
    identities.add(_BlockIdentity(blockId: selectedItemId));
    if (afterItemIds.isNotEmpty) {
      identities.add(
        _BlockIdentity(
          blockId: beforeItemIds.isEmpty
              ? sourceIdentity.blockId
              : registry.nextNodeId(),
          listItemIds: afterItemIds,
        ),
      );
    }
    return identities;
  }

  List<LessonBlock> _toggleHeadingForListItem(
    LessonListBlock source,
    int itemIndex,
  ) {
    final selectedItem = source.items[itemIndex];
    final beforeItems = source.items.take(itemIndex).toList(growable: false);
    final afterItems = source.items.skip(itemIndex + 1).toList(growable: false);
    return <LessonBlock>[
      if (beforeItems.isNotEmpty) _listBlockLike(source, beforeItems),
      LessonHeadingBlock(
        id: selectedItem.id,
        level: _defaultHeadingLevel,
        children: selectedItem.children,
      ),
      if (afterItems.isNotEmpty) _listBlockLike(source, afterItems),
    ];
  }

  _EditorTarget? _activeTextTarget() {
    return _resolveActiveTextTarget().target;
  }

  _ActiveTextTargetResolution _resolveActiveTextTarget() {
    final target = _selectedTarget;
    if (target == null) {
      return const _ActiveTextTargetResolution.failed(
        LessonEditorCommandFailure.emptyTarget,
      );
    }
    if (!_identityRegistryMatchesDocument()) {
      return const _ActiveTextTargetResolution.failed(
        LessonEditorCommandFailure.identityRegistryMismatch,
      );
    }
    if (target is! _BlockTextTarget && target is! _ListItemTextTarget) {
      return const _ActiveTextTargetResolution.failed(
        LessonEditorCommandFailure.unsupportedTarget,
      );
    }
    if (!_targetExists(target)) {
      return const _ActiveTextTargetResolution.failed(
        LessonEditorCommandFailure.staleSelection,
      );
    }
    final key = _controlKeyForTarget(target);
    if (key == null) {
      return const _ActiveTextTargetResolution.failed(
        LessonEditorCommandFailure.invalidSelection,
      );
    }
    final selection = _controllers[key]?.selection;
    if (selection == null || !selection.isValid) {
      return const _ActiveTextTargetResolution.failed(
        LessonEditorCommandFailure.invalidSelection,
      );
    }
    return _ActiveTextTargetResolution.resolved(
      target: target,
      revision: _selectedTargetRevision,
    );
  }

  _SelectedTextRange? _selectedTextRange() {
    return _resolveSelectedTextRange().range;
  }

  _SelectedTextRangeResolution _resolveSelectedTextRange() {
    final targetResult = _resolveActiveTextTarget();
    final target = targetResult.target;
    if (target == null) {
      return _SelectedTextRangeResolution.failed(targetResult.failure);
    }
    final children = _childrenForTarget(target);
    final text = _plainText(children);
    final length = text.length;
    if (length == 0) {
      return const _SelectedTextRangeResolution.failed(
        LessonEditorCommandFailure.emptyTarget,
      );
    }
    final key = _controlKeyForTarget(target);
    if (key == null) {
      return const _SelectedTextRangeResolution.failed(
        LessonEditorCommandFailure.invalidSelection,
      );
    }
    final controller = _controllers[key];
    if (controller == null) {
      return const _SelectedTextRangeResolution.failed(
        LessonEditorCommandFailure.invalidSelection,
      );
    }
    if (controller.text != text) {
      return const _SelectedTextRangeResolution.failed(
        LessonEditorCommandFailure.textMismatch,
      );
    }
    final selection = controller.selection;
    if (!selection.isValid) {
      return const _SelectedTextRangeResolution.failed(
        LessonEditorCommandFailure.invalidSelection,
      );
    }
    if (selection.isCollapsed) {
      return const _SelectedTextRangeResolution.failed(
        LessonEditorCommandFailure.collapsedSelection,
      );
    }
    final start = selection.start;
    final end = selection.end;
    if (start < 0 || end < 0 || start > length || end > length) {
      return const _SelectedTextRangeResolution.failed(
        LessonEditorCommandFailure.invalidRange,
      );
    }
    if (start == end) {
      return const _SelectedTextRangeResolution.failed(
        LessonEditorCommandFailure.collapsedSelection,
      );
    }
    return _SelectedTextRangeResolution.resolved(
      _SelectedTextRange(
        target: target,
        revision: targetResult.revision ?? _revision,
        start: start < end ? start : end,
        end: end > start ? end : start,
      ),
    );
  }

  void _appendParagraph() {
    final insertionIndex = _document.blocks.length;
    const block = LessonParagraphBlock(
      children: <LessonTextRun>[LessonTextRun('')],
    );
    final next = _document.insertBlock(insertionIndex, block);
    final nextRegistry = _identityRegistry.copy();
    final identity = nextRegistry.createBlockIdentity(block);
    nextRegistry.blocks.insert(insertionIndex, identity);
    _applyDocument(next, identityRegistry: nextRegistry);
    final nextTarget = _BlockTextTarget(identity.blockId);
    widget.onInsertionIndexChanged?.call(
      _insertionIndexForTarget(nextTarget) ?? next.blocks.length,
    );
    _setSelectedTargetForCurrentRevision(nextTarget);
  }

  void _moveBlock(_EditorNodeId blockId, int targetIndex) {
    if (!widget.enabled) return;
    final blockIndex = _blockIndexFor(blockId);
    if (blockIndex == null) return;
    if (targetIndex < 0 || targetIndex >= _document.blocks.length) {
      return;
    }
    if (blockIndex == targetIndex) return;
    final next = _document.moveBlock(blockIndex, targetIndex);
    final nextRegistry = _identityRegistry.copy();
    final identity = nextRegistry.blocks.removeAt(blockIndex);
    nextRegistry.blocks.insert(targetIndex, identity);
    _applyDocument(next, identityRegistry: nextRegistry);
    final nextTarget = _BlockTarget(blockId);
    widget.onInsertionIndexChanged?.call(
      _insertionIndexForTarget(nextTarget) ?? targetIndex + 1,
    );
    _setSelectedTargetForCurrentRevision(nextTarget);
  }

  void _moveBlockUp(_EditorNodeId blockId) {
    final blockIndex = _blockIndexFor(blockId);
    if (blockIndex == null) return;
    _moveBlock(blockId, blockIndex - 1);
  }

  void _moveBlockDown(_EditorNodeId blockId) {
    final blockIndex = _blockIndexFor(blockId);
    if (blockIndex == null) return;
    _moveBlock(blockId, blockIndex + 1);
  }

  void _deleteBlock(_EditorNodeId blockId) {
    if (!widget.enabled) return;
    final blockIndex = _blockIndexFor(blockId);
    if (blockIndex == null) return;
    final removedIdentity = _identityRegistry.blocks[blockIndex];
    final selectedWasRemoved = _targetBelongsToIdentity(
      _selectedTarget,
      removedIdentity,
    );

    final next = _document.removeBlock(blockIndex);
    final nextRegistry = _identityRegistry.copy();
    final removed = nextRegistry.blocks.removeAt(blockIndex);
    _disposeRemovedIdentityKeys([removed], const <_BlockIdentity>[]);
    _applyDocument(next, identityRegistry: nextRegistry);
    if (!selectedWasRemoved) return;

    final nextTarget = next.blocks.isEmpty
        ? null
        : _targetForBlockIndex(
            blockIndex.clamp(0, next.blocks.length - 1).toInt(),
          );
    widget.onInsertionIndexChanged?.call(
      nextTarget == null ? 0 : _insertionIndexForTarget(nextTarget) ?? 0,
    );
    _setSelectedTargetForCurrentRevision(nextTarget);
  }

  void _deleteSelectedBlock() {
    final target = _selectedTarget;
    if (target == null) return;
    final blockId = _owningBlockIdForTarget(target);
    if (blockId == null) return;
    _deleteBlock(blockId);
  }

  bool _isEmptyTextBlockTarget(_EditorTarget target) {
    if (target is! _BlockTextTarget) return false;
    final blockId = target.blockId;
    final blockIndex = _blockIndexFor(blockId);
    if (blockIndex == null) return false;
    final block = _document.blocks[blockIndex];
    if (block is LessonParagraphBlock) {
      return _plainText(block.children).isEmpty;
    }
    if (block is LessonHeadingBlock) {
      return _plainText(block.children).isEmpty;
    }
    return false;
  }

  bool _shouldDeleteEmptyBlockFromKey(
    _EditorTarget target,
    TextEditingController controller,
  ) {
    if (!widget.enabled || controller.text.isNotEmpty) return false;
    return _targetExists(target) && _isEmptyTextBlockTarget(target);
  }

  void _insertFirstParagraphFromEmptyDocument(String text) {
    if (!widget.enabled) return;
    final normalizedText = text.replaceAll('\r\n', '\n');
    if (normalizedText.isEmpty || _document.blocks.isNotEmpty) return;
    final block = LessonParagraphBlock(
      children: <LessonTextRun>[LessonTextRun(normalizedText)],
    );
    final next = LessonDocument(
      blocks: List<LessonBlock>.unmodifiable([block]),
    );
    final nextRegistry = _identityRegistry.copy();
    final identity = nextRegistry.createBlockIdentity(block);
    nextRegistry.blocks.add(identity);
    _applyDocument(next, identityRegistry: nextRegistry);
    widget.onInsertionIndexChanged?.call(1);
    _setSelectedTargetForCurrentRevision(_BlockTextTarget(identity.blockId));
  }

  void _updateCtaBlock(
    _EditorNodeId blockId, {
    String? label,
    String? targetUrl,
  }) {
    final blockIndex = _blockIndexFor(blockId);
    if (blockIndex == null) return;
    final block = _document.blocks[blockIndex];
    if (block is! LessonCtaBlock) return;
    final nextBlocks = List<LessonBlock>.from(_document.blocks);
    nextBlocks[blockIndex] = LessonCtaBlock(
      id: block.id,
      label: label ?? block.label,
      targetUrl: targetUrl ?? block.targetUrl,
    );
    _emit(LessonDocument(blocks: List<LessonBlock>.unmodifiable(nextBlocks)));
  }

  @override
  Widget build(BuildContext context) {
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
            onHeading: _convertSelectedHeading,
            onBulletList: () =>
                _convertSelectedBlock(_BlockConversion.bulletList),
            onOrderedList: () =>
                _convertSelectedBlock(_BlockConversion.orderedList),
            onAddParagraph: _appendParagraph,
            onDeleteBlock: _deleteSelectedBlock,
          ),
          const Divider(height: 1),
          Expanded(
            child: DecoratedBox(
              key: const ValueKey<String>(
                'lesson_document_continuous_writing_surface',
              ),
              decoration: const BoxDecoration(color: Colors.white),
              child: _document.blocks.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [_buildEmptyDocumentAffordance(context)],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: _document.blocks.length,
                      itemBuilder: (context, blockIndex) {
                        final block = _document.blocks[blockIndex];
                        final identity = _identityAtBlockIndex(blockIndex);
                        if (identity == null) return const SizedBox.shrink();
                        return _buildBlockEditor(
                          context,
                          block,
                          blockIndex,
                          identity,
                        );
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
    return lessonHeadingPresentationStyle(
      theme,
      level: level,
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

  Widget _buildEmptyDocumentAffordance(BuildContext context) {
    final textStyle = _paragraphStyle(context);
    return Semantics(
      label: 'Tom lektionsyta',
      textField: true,
      child: TextField(
        key: const ValueKey<String>('lesson_document_editor_block_0'),
        enabled: widget.enabled,
        controller: _emptyDocumentController,
        focusNode: _emptyDocumentFocusNode,
        style: textStyle,
        minLines: 1,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          hintText: 'Skriv lektionsinnehall',
          hintStyle: textStyle.copyWith(
            color: textStyle.color?.withValues(alpha: 0.34),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        onTap: () {
          widget.onInsertionIndexChanged?.call(0);
          if (_selectedTarget != null) {
            _setSelectedTargetForCurrentRevision(null);
          }
        },
        onChanged: _insertFirstParagraphFromEmptyDocument,
      ),
    );
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

  Widget _buildBlockMoveControls({
    required _EditorNodeId blockId,
    required int blockIndex,
    required String keyPrefix,
    required String upTooltip,
    required String downTooltip,
  }) {
    final canMoveUp = widget.enabled && blockIndex > 0;
    final canMoveDown =
        widget.enabled && blockIndex < _document.blocks.length - 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey<String>('${keyPrefix}_move_up_${blockId.keyValue}'),
          tooltip: upTooltip,
          onPressed: canMoveUp ? () => _moveBlockUp(blockId) : null,
          icon: const Icon(Icons.keyboard_arrow_up),
        ),
        IconButton(
          key: ValueKey<String>('${keyPrefix}_move_down_${blockId.keyValue}'),
          tooltip: downTooltip,
          onPressed: canMoveDown ? () => _moveBlockDown(blockId) : null,
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
      ],
    );
  }

  Widget _buildBlockEditor(
    BuildContext context,
    LessonBlock block,
    int blockIndex,
    _BlockIdentity identity,
  ) {
    if (block is LessonParagraphBlock) {
      return _buildFlowingBlockPadding(
        block: block,
        blockIndex: blockIndex,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildTextField(
                context,
                target: _BlockTextTarget(identity.blockId),
                semanticsLabel: 'Stycke',
                children: block.children,
                textStyle: _paragraphStyle(context),
              ),
            ),
            const SizedBox(width: 8),
            _buildBlockMoveControls(
              blockId: identity.blockId,
              blockIndex: blockIndex,
              keyPrefix: 'lesson_document_text',
              upTooltip: 'Flytta text upp',
              downTooltip: 'Flytta text ned',
            ),
          ],
        ),
      );
    }
    if (block is LessonHeadingBlock) {
      return _buildFlowingBlockPadding(
        block: block,
        blockIndex: blockIndex,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildTextField(
                context,
                target: _BlockTextTarget(identity.blockId),
                semanticsLabel: 'Rubrik H${block.level}',
                children: block.children,
                textStyle: _headingStyle(context, block.level),
              ),
            ),
            const SizedBox(width: 8),
            _buildBlockMoveControls(
              blockId: identity.blockId,
              blockIndex: blockIndex,
              keyPrefix: 'lesson_document_text',
              upTooltip: 'Flytta text upp',
              downTooltip: 'Flytta text ned',
            ),
          ],
        ),
      );
    }
    if (block is LessonListBlock) {
      if (identity.listItemIds.length != block.items.length) {
        return const SizedBox.shrink();
      }
      final ordered = block.type == 'ordered_list';
      return _buildFlowingBlockPadding(
        block: block,
        blockIndex: blockIndex,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
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
                                ordered
                                    ? '${itemIndex + (block.start ?? 1)}.'
                                    : '-',
                                textAlign: TextAlign.right,
                                style: _listMarkerStyle(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              context,
                              target: _ListItemTextTarget(
                                identity.listItemIds[itemIndex],
                              ),
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
            ),
            const SizedBox(width: 8),
            _buildBlockMoveControls(
              blockId: identity.blockId,
              blockIndex: blockIndex,
              keyPrefix: 'lesson_document_text',
              upTooltip: 'Flytta text upp',
              downTooltip: 'Flytta text ned',
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
      return _buildFlowingBlockPadding(
        block: block,
        blockIndex: blockIndex,
        child: Padding(
          key: ValueKey<String>(
            'lesson_document_media_${identity.blockId.keyValue}',
          ),
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
              _buildBlockMoveControls(
                blockId: identity.blockId,
                blockIndex: blockIndex,
                keyPrefix: 'lesson_document_media',
                upTooltip: 'Flytta media upp',
                downTooltip: 'Flytta media ned',
              ),
            ],
          ),
        ),
      );
    }
    if (block is LessonCtaBlock) {
      final theme = Theme.of(context);
      final labelTarget = _CtaFieldTarget(identity.blockId, _CtaField.label);
      final urlTarget = _CtaFieldTarget(identity.blockId, _CtaField.url);
      final labelKey = _ctaControlKey(identity.blockId, _CtaField.label);
      final urlKey = _ctaControlKey(identity.blockId, _CtaField.url);
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
                key: ValueKey<String>('lesson_document_${labelKey.value}'),
                enabled: widget.enabled,
                controller: _controllerFor(labelKey, block.label),
                focusNode: _focusNodeFor(labelKey, labelTarget),
                style: _paragraphStyle(context),
                decoration: const InputDecoration(
                  hintText: 'CTA text',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onTap: () => _select(labelTarget),
                onChanged: (value) =>
                    _updateCtaBlock(identity.blockId, label: value),
              ),
              TextField(
                key: ValueKey<String>('lesson_document_${urlKey.value}'),
                enabled: widget.enabled,
                controller: _controllerFor(urlKey, block.targetUrl),
                focusNode: _focusNodeFor(urlKey, urlTarget),
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
                onTap: () => _select(urlTarget),
                onChanged: (value) =>
                    _updateCtaBlock(identity.blockId, targetUrl: value),
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
    final key = _controlKeyForTarget(target);
    if (key == null) return const SizedBox.shrink();
    final controller = _controllerFor(key, _plainText(children), children);
    final focusNode = _focusNodeFor(key, target);
    final deleteEmptyBlockShortcuts =
        _shouldDeleteEmptyBlockFromKey(target, controller)
        ? <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.backspace): () =>
                _deleteTextBlockTarget(target),
            const SingleActivator(LogicalKeyboardKey.delete): () =>
                _deleteTextBlockTarget(target),
          }
        : const <ShortcutActivator, VoidCallback>{};
    return Semantics(
      label: semanticsLabel,
      textField: true,
      child: CallbackShortcuts(
        bindings: deleteEmptyBlockShortcuts,
        child: TextField(
          key: ValueKey<String>('lesson_document_editor_${key.value}'),
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
      ),
    );
  }

  void _deleteTextBlockTarget(_EditorTarget target) {
    final blockId = _owningBlockIdForTarget(target);
    if (blockId == null) return;
    _deleteBlock(blockId);
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
          TextSpan(text: run.text, style: lessonTextRunStyle(base, run)),
      ],
    );
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
    required this.onDeleteBlock,
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
  final VoidCallback onDeleteBlock;

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
          _toolbarButton(
            key: const Key('lesson_document_toolbar_delete_block'),
            icon: Icons.delete_outline_rounded,
            label: 'Ta bort',
            onPressed: onDeleteBlock,
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

class _ActiveTextTargetResolution {
  const _ActiveTextTargetResolution.resolved({
    required this.target,
    required this.revision,
  }) : failure = null;

  const _ActiveTextTargetResolution.failed(this.failure)
    : target = null,
      revision = null;

  final _EditorTarget? target;
  final int? revision;
  final LessonEditorCommandFailure? failure;
}

class _SelectedTextRangeResolution {
  const _SelectedTextRangeResolution.resolved(this.range) : failure = null;

  const _SelectedTextRangeResolution.failed(this.failure) : range = null;

  final _SelectedTextRange? range;
  final LessonEditorCommandFailure? failure;
}

class _SelectedTextRange {
  const _SelectedTextRange({
    required this.target,
    required this.revision,
    required this.start,
    required this.end,
  });

  final _EditorTarget target;
  final int revision;
  final int start;
  final int end;
}

final class _EditorNodeId {
  const _EditorNodeId(this.value);

  final int value;

  String get keyValue => 'node_$value';

  @override
  bool operator ==(Object other) {
    return other is _EditorNodeId && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}

final class _BlockIdentity {
  const _BlockIdentity({
    required this.blockId,
    this.listItemIds = const <_EditorNodeId>[],
  });

  final _EditorNodeId blockId;
  final List<_EditorNodeId> listItemIds;

  _BlockIdentity copy() {
    return _BlockIdentity(
      blockId: blockId,
      listItemIds: List<_EditorNodeId>.unmodifiable(listItemIds),
    );
  }
}

final class _EditorIdentityRegistry {
  _EditorIdentityRegistry._({
    required List<_BlockIdentity> blocks,
    required int nextValue,
  }) : blocks = List<_BlockIdentity>.of(blocks),
       _nextValue = nextValue;

  factory _EditorIdentityRegistry.fromDocument(LessonDocument document) {
    final registry = _EditorIdentityRegistry._(
      blocks: const <_BlockIdentity>[],
      nextValue: 0,
    );
    for (final block in document.blocks) {
      registry.blocks.add(registry.createBlockIdentity(block));
    }
    return registry;
  }

  final List<_BlockIdentity> blocks;
  int _nextValue;

  _EditorIdentityRegistry copy() {
    return _EditorIdentityRegistry._(
      blocks: [for (final block in blocks) block.copy()],
      nextValue: _nextValue,
    );
  }

  _EditorNodeId nextNodeId() {
    final nodeId = _EditorNodeId(_nextValue);
    _nextValue += 1;
    return nodeId;
  }

  _BlockIdentity createBlockIdentity(LessonBlock block) {
    return _BlockIdentity(
      blockId: nextNodeId(),
      listItemIds: block is LessonListBlock
          ? [
              for (var index = 0; index < block.items.length; index += 1)
                nextNodeId(),
            ]
          : const <_EditorNodeId>[],
    );
  }
}

final class _EditorControlKey {
  const _EditorControlKey._(this.value);

  factory _EditorControlKey.node(_EditorNodeId nodeId) {
    return _EditorControlKey._(nodeId.keyValue);
  }

  factory _EditorControlKey.cta(_EditorNodeId blockId, _CtaField field) {
    return _EditorControlKey._('cta:${blockId.keyValue}:${field.name}');
  }

  final String value;

  @override
  bool operator ==(Object other) {
    return other is _EditorControlKey && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}

enum _CtaField { label, url }

sealed class _EditorTarget {
  const _EditorTarget();
}

final class _BlockTextTarget extends _EditorTarget {
  const _BlockTextTarget(this.blockId);

  final _EditorNodeId blockId;

  @override
  bool operator ==(Object other) {
    return other is _BlockTextTarget && other.blockId == blockId;
  }

  @override
  int get hashCode => Object.hash(_BlockTextTarget, blockId);
}

final class _ListItemTextTarget extends _EditorTarget {
  const _ListItemTextTarget(this.itemId);

  final _EditorNodeId itemId;

  @override
  bool operator ==(Object other) {
    return other is _ListItemTextTarget && other.itemId == itemId;
  }

  @override
  int get hashCode => Object.hash(_ListItemTextTarget, itemId);
}

final class _BlockTarget extends _EditorTarget {
  const _BlockTarget(this.blockId);

  final _EditorNodeId blockId;

  @override
  bool operator ==(Object other) {
    return other is _BlockTarget && other.blockId == blockId;
  }

  @override
  int get hashCode => Object.hash(_BlockTarget, blockId);
}

final class _CtaFieldTarget extends _EditorTarget {
  const _CtaFieldTarget(this.blockId, this.field);

  final _EditorNodeId blockId;
  final _CtaField field;

  @override
  bool operator ==(Object other) {
    return other is _CtaFieldTarget &&
        other.blockId == blockId &&
        other.field == field;
  }

  @override
  int get hashCode => Object.hash(_CtaFieldTarget, blockId, field);
}

final class _ListItemLocation {
  const _ListItemLocation({
    required this.blockIndex,
    required this.itemIndex,
    required this.block,
    required this.blockIdentity,
  });

  final int blockIndex;
  final int itemIndex;
  final LessonListBlock block;
  final _BlockIdentity blockIdentity;
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
  final previousText = _plainText(previous);
  if (previousText == text) {
    return List<LessonTextRun>.unmodifiable(previous);
  }

  final prefixLength = _commonPrefixLength(previousText, text);
  final suffixLength = _commonSuffixLength(previousText, text, prefixLength);
  final replacedStart = prefixLength;
  final replacedEnd = previousText.length - suffixLength;
  final insertedText = text.substring(prefixLength, text.length - suffixLength);
  final next = <LessonTextRun>[
    ..._sliceRuns(previous, 0, replacedStart),
    if (insertedText.isNotEmpty)
      LessonTextRun(
        insertedText,
        marks: _marksForReplacement(
          previous,
          start: replacedStart,
          end: replacedEnd,
        ),
      ),
    ..._sliceRuns(previous, replacedEnd, previousText.length),
  ];
  final merged = _mergeReplacementRuns(next);
  if (merged.isEmpty) {
    return const <LessonTextRun>[LessonTextRun('')];
  }
  return List<LessonTextRun>.unmodifiable(merged);
}

int _commonPrefixLength(String previousText, String nextText) {
  final max = previousText.length < nextText.length
      ? previousText.length
      : nextText.length;
  var index = 0;
  while (index < max && previousText[index] == nextText[index]) {
    index += 1;
  }
  return index;
}

int _commonSuffixLength(
  String previousText,
  String nextText,
  int prefixLength,
) {
  final previousAvailable = previousText.length - prefixLength;
  final nextAvailable = nextText.length - prefixLength;
  final max = previousAvailable < nextAvailable
      ? previousAvailable
      : nextAvailable;
  var suffix = 0;
  while (suffix < max &&
      previousText[previousText.length - 1 - suffix] ==
          nextText[nextText.length - 1 - suffix]) {
    suffix += 1;
  }
  return suffix;
}

List<LessonInlineMark> _marksForReplacement(
  List<LessonTextRun> previous, {
  required int start,
  required int end,
}) {
  if (start == end) {
    return _boundaryMarks(previous, start);
  }
  final uniformSelection = _uniformMarksOrNull(
    _sliceRuns(previous, start, end),
  );
  if (uniformSelection != null) {
    return uniformSelection;
  }
  return const <LessonInlineMark>[];
}

List<LessonInlineMark>? _uniformMarksOrNull(List<LessonTextRun> runs) {
  if (runs.isEmpty) return const <LessonInlineMark>[];
  final first = runs.first.marks;
  for (final run in runs.skip(1)) {
    if (!_sameMarkSet(first, run.marks)) {
      return null;
    }
  }
  return List<LessonInlineMark>.unmodifiable(first);
}

List<LessonInlineMark> _boundaryMarks(List<LessonTextRun> runs, int offset) {
  final left = _marksAdjacentToOffset(runs, offset, preferLeft: true);
  final right = _marksAdjacentToOffset(runs, offset, preferLeft: false);
  if (left == null && right == null) {
    return const <LessonInlineMark>[];
  }
  if (left == null) {
    return right!;
  }
  if (right == null) {
    return left;
  }
  return _sameMarkSet(left, right) ? left : const <LessonInlineMark>[];
}

List<LessonInlineMark>? _marksAdjacentToOffset(
  List<LessonTextRun> runs,
  int offset, {
  required bool preferLeft,
}) {
  var current = 0;
  for (final run in runs) {
    final start = current;
    final end = start + run.text.length;
    current = end;
    if (offset > start && offset < end) {
      return List<LessonInlineMark>.unmodifiable(run.marks);
    }
    if (preferLeft && offset == end) {
      return List<LessonInlineMark>.unmodifiable(run.marks);
    }
    if (!preferLeft && offset == start) {
      return List<LessonInlineMark>.unmodifiable(run.marks);
    }
  }
  return null;
}

List<LessonTextRun> _mergeReplacementRuns(List<LessonTextRun> runs) {
  final merged = <LessonTextRun>[];
  for (final run in runs) {
    if (run.text.isEmpty) {
      continue;
    }
    if (merged.isNotEmpty && _sameMarkSet(merged.last.marks, run.marks)) {
      final previous = merged.removeLast();
      merged.add(previous.copyWith(text: '${previous.text}${run.text}'));
    } else {
      merged.add(run);
    }
  }
  return merged;
}

bool _sameMarkSet(List<LessonInlineMark> left, List<LessonInlineMark> right) {
  if (left.length != right.length) {
    return false;
  }
  final rightSignatures = right.map(_markSignature).toSet();
  if (rightSignatures.length != right.length) {
    return false;
  }
  for (final mark in left) {
    if (!rightSignatures.contains(_markSignature(mark))) {
      return false;
    }
  }
  return true;
}

String _markSignature(LessonInlineMark mark) {
  return jsonEncode(mark.toJson());
}

String _plainText(List<LessonTextRun> children) {
  return children.map((child) => child.text).join();
}
