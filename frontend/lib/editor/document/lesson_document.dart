import 'dart:convert';

const lessonDocumentSchemaVersion = 'lesson_document_v1';

const _allowedBasicMarks = {'bold', 'italic', 'underline'};
const _allowedMediaTypes = {'image', 'audio', 'video', 'document'};
final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

sealed class LessonInlineMark {
  const LessonInlineMark();

  String get type;

  Object toJson();

  static const bold = LessonBasicMark('bold');
  static const italic = LessonBasicMark('italic');
  static const underline = LessonBasicMark('underline');

  static LessonInlineMark link(String href) => LessonLinkMark(href);

  static LessonInlineMark fromJson(Object? payload) {
    if (payload is String) {
      if (!_allowedBasicMarks.contains(payload)) {
        throw FormatException('Unsupported inline mark: $payload');
      }
      return LessonBasicMark(payload);
    }
    if (payload is Map) {
      final map = Map<String, Object?>.from(payload);
      _requireExactKeys(map, {'type', 'href'}, 'mark');
      final type = _requiredString(map, 'type', 'mark');
      if (type != 'link') {
        throw FormatException('Unsupported object mark: $type');
      }
      final href = _requiredString(map, 'href', 'mark');
      _validateTargetUrl(href, 'mark.href');
      return LessonLinkMark(href);
    }
    throw const FormatException('Inline mark must be a string or object');
  }
}

final class LessonBasicMark extends LessonInlineMark {
  const LessonBasicMark(this.type);

  @override
  final String type;

  @override
  Object toJson() => type;
}

final class LessonLinkMark extends LessonInlineMark {
  const LessonLinkMark(this.href);

  final String href;

  @override
  String get type => 'link';

  @override
  Object toJson() => {'type': 'link', 'href': href};
}

final class LessonTextRun {
  const LessonTextRun(this.text, {this.marks = const <LessonInlineMark>[]});

  final String text;
  final List<LessonInlineMark> marks;

  Map<String, Object?> toJson() => {
    'text': text,
    if (marks.isNotEmpty) 'marks': marks.map((mark) => mark.toJson()).toList(),
  };

  LessonTextRun copyWith({String? text, List<LessonInlineMark>? marks}) {
    return LessonTextRun(text ?? this.text, marks: marks ?? this.marks);
  }

  static LessonTextRun fromJson(Object? payload) {
    if (payload is! Map) {
      throw const FormatException('Text run must be an object');
    }
    final map = Map<String, Object?>.from(payload);
    _requireExactKeys(map, {'text', 'marks'}, 'text');
    final rawMarks = map['marks'];
    final marks = rawMarks == null
        ? const <LessonInlineMark>[]
        : _requiredList(
            rawMarks,
            'text.marks',
          ).map(LessonInlineMark.fromJson).toList(growable: false);
    _validateNoDuplicateMarks(marks, 'text.marks');
    return LessonTextRun(_requiredString(map, 'text', 'text'), marks: marks);
  }
}

sealed class LessonBlock {
  const LessonBlock({this.id});

  final String? id;
  String get type;
  Map<String, Object?> toJson();

  static LessonBlock fromJson(Object? payload) {
    if (payload is! Map) {
      throw const FormatException('Block must be an object');
    }
    final map = Map<String, Object?>.from(payload);
    final type = _requiredString(map, 'type', 'block');
    return switch (type) {
      'paragraph' => LessonParagraphBlock.fromJsonMap(map),
      'heading' => LessonHeadingBlock.fromJsonMap(map),
      'bullet_list' => LessonListBlock.fromJsonMap(map),
      'ordered_list' => LessonListBlock.fromJsonMap(map),
      'media' => LessonMediaBlock.fromJsonMap(map),
      'cta' => LessonCtaBlock.fromJsonMap(map),
      _ => throw FormatException('Unsupported block type: $type'),
    };
  }
}

final class LessonParagraphBlock extends LessonBlock {
  const LessonParagraphBlock({required this.children, super.id});

  final List<LessonTextRun> children;

  @override
  String get type => 'paragraph';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    if (id != null) 'id': id,
    'children': children.map((child) => child.toJson()).toList(),
  };

  LessonParagraphBlock copyWith({List<LessonTextRun>? children}) {
    return LessonParagraphBlock(id: id, children: children ?? this.children);
  }

  static LessonParagraphBlock fromJsonMap(Map<String, Object?> map) {
    _requireExactKeys(map, {'type', 'id', 'children'}, 'paragraph');
    return LessonParagraphBlock(
      id: _optionalString(map, 'id', 'paragraph'),
      children: _textRuns(map['children'], 'paragraph.children'),
    );
  }
}

final class LessonHeadingBlock extends LessonBlock {
  const LessonHeadingBlock({
    required this.level,
    required this.children,
    super.id,
  });

  final int level;
  final List<LessonTextRun> children;

  @override
  String get type => 'heading';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    if (id != null) 'id': id,
    'level': level,
    'children': children.map((child) => child.toJson()).toList(),
  };

  LessonHeadingBlock copyWith({List<LessonTextRun>? children}) {
    return LessonHeadingBlock(
      id: id,
      level: level,
      children: children ?? this.children,
    );
  }

  static LessonHeadingBlock fromJsonMap(Map<String, Object?> map) {
    _requireExactKeys(map, {'type', 'id', 'level', 'children'}, 'heading');
    final level = _requiredInt(map, 'level', 'heading');
    if (level < 1 || level > 6) {
      throw const FormatException('heading.level must be 1 through 6');
    }
    return LessonHeadingBlock(
      id: _optionalString(map, 'id', 'heading'),
      level: level,
      children: _textRuns(map['children'], 'heading.children'),
    );
  }
}

final class LessonListItem {
  const LessonListItem({required this.children, this.id});

  final String? id;
  final List<LessonTextRun> children;

  Map<String, Object?> toJson() => {
    if (id != null) 'id': id,
    'children': children.map((child) => child.toJson()).toList(),
  };

  LessonListItem copyWith({List<LessonTextRun>? children}) {
    return LessonListItem(id: id, children: children ?? this.children);
  }

  static LessonListItem fromJson(Object? payload) {
    if (payload is! Map) {
      throw const FormatException('List item must be an object');
    }
    final map = Map<String, Object?>.from(payload);
    _requireExactKeys(map, {'id', 'children'}, 'list item');
    return LessonListItem(
      id: _optionalString(map, 'id', 'list item'),
      children: _textRuns(map['children'], 'list item.children'),
    );
  }
}

final class LessonListBlock extends LessonBlock {
  const LessonListBlock.bullet({required this.items, super.id}) : start = null;

  const LessonListBlock.ordered({
    required this.items,
    this.start = 1,
    super.id,
  });

  final List<LessonListItem> items;
  final int? start;

  @override
  String get type => start == null ? 'bullet_list' : 'ordered_list';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    if (id != null) 'id': id,
    if (start != null && start != 1) 'start': start,
    'items': items.map((item) => item.toJson()).toList(),
  };

  LessonListBlock copyWith({List<LessonListItem>? items}) {
    return start == null
        ? LessonListBlock.bullet(id: id, items: items ?? this.items)
        : LessonListBlock.ordered(
            id: id,
            start: start,
            items: items ?? this.items,
          );
  }

  static LessonListBlock fromJsonMap(Map<String, Object?> map) {
    final type = _requiredString(map, 'type', 'list');
    if (type == 'bullet_list') {
      _requireExactKeys(map, {'type', 'id', 'items'}, 'bullet_list');
      return LessonListBlock.bullet(
        id: _optionalString(map, 'id', 'bullet_list'),
        items: _listItems(map['items'], 'bullet_list.items'),
      );
    }
    _requireExactKeys(map, {'type', 'id', 'start', 'items'}, 'ordered_list');
    final start = map.containsKey('start')
        ? _requiredInt(map, 'start', 'ordered_list')
        : 1;
    if (start < 1) {
      throw const FormatException('ordered_list.start must be positive');
    }
    return LessonListBlock.ordered(
      id: _optionalString(map, 'id', 'ordered_list'),
      start: start,
      items: _listItems(map['items'], 'ordered_list.items'),
    );
  }
}

final class LessonMediaBlock extends LessonBlock {
  const LessonMediaBlock({
    required this.mediaType,
    required this.lessonMediaId,
    super.id,
  });

  final String mediaType;
  final String lessonMediaId;

  @override
  String get type => 'media';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    if (id != null) 'id': id,
    'media_type': mediaType,
    'lesson_media_id': lessonMediaId,
  };

  static LessonMediaBlock fromJsonMap(Map<String, Object?> map) {
    _requireExactKeys(map, {
      'type',
      'id',
      'media_type',
      'lesson_media_id',
    }, 'media');
    final mediaType = _requiredString(map, 'media_type', 'media');
    if (!_allowedMediaTypes.contains(mediaType)) {
      throw FormatException('Unsupported media_type: $mediaType');
    }
    final lessonMediaId = _requiredString(map, 'lesson_media_id', 'media');
    if (!_uuidPattern.hasMatch(lessonMediaId)) {
      throw const FormatException('media.lesson_media_id must be a UUID');
    }
    return LessonMediaBlock(
      id: _optionalString(map, 'id', 'media'),
      mediaType: mediaType,
      lessonMediaId: lessonMediaId,
    );
  }
}

final class LessonCtaBlock extends LessonBlock {
  const LessonCtaBlock({
    required this.label,
    required this.targetUrl,
    super.id,
  });

  final String label;
  final String targetUrl;

  @override
  String get type => 'cta';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    if (id != null) 'id': id,
    'label': label,
    'target_url': targetUrl,
  };

  static LessonCtaBlock fromJsonMap(Map<String, Object?> map) {
    _requireExactKeys(map, {'type', 'id', 'label', 'target_url'}, 'cta');
    final label = _requiredString(map, 'label', 'cta');
    if (label.trim().isEmpty) {
      throw const FormatException('cta.label must not be blank');
    }
    final targetUrl = _requiredString(map, 'target_url', 'cta');
    _validateTargetUrl(targetUrl, 'cta.target_url');
    return LessonCtaBlock(
      id: _optionalString(map, 'id', 'cta'),
      label: label,
      targetUrl: targetUrl,
    );
  }
}

final class LessonDocument {
  const LessonDocument({this.blocks = const <LessonBlock>[]});

  final List<LessonBlock> blocks;

  Map<String, Object?> toJson() => {
    'schema_version': lessonDocumentSchemaVersion,
    'blocks': blocks.map((block) => block.toJson()).toList(),
  };

  String toCanonicalJsonString() => jsonEncode(_deepSort(toJson()));

  LessonDocument insertBlock(int index, LessonBlock block) {
    final next = [...blocks]..insert(index, block);
    return LessonDocument(blocks: List<LessonBlock>.unmodifiable(next));
  }

  LessonDocument moveBlock(int fromIndex, int toIndex) {
    RangeError.checkValidIndex(fromIndex, blocks, 'fromIndex');
    RangeError.checkValidIndex(toIndex, blocks, 'toIndex');
    if (fromIndex == toIndex) {
      return this;
    }
    final next = [...blocks];
    final block = next.removeAt(fromIndex);
    next.insert(toIndex, block);
    return LessonDocument(blocks: List<LessonBlock>.unmodifiable(next));
  }

  LessonDocument moveBlockUp(int index) {
    RangeError.checkValidIndex(index, blocks, 'index');
    if (index == 0) {
      return this;
    }
    return moveBlock(index, index - 1);
  }

  LessonDocument moveBlockDown(int index) {
    RangeError.checkValidIndex(index, blocks, 'index');
    if (index == blocks.length - 1) {
      return this;
    }
    return moveBlock(index, index + 1);
  }

  LessonDocument insertParagraph(int index, List<LessonTextRun> children) {
    return insertBlock(index, LessonParagraphBlock(children: children));
  }

  LessonDocument insertHeading(
    int index, {
    required int level,
    required List<LessonTextRun> children,
  }) {
    return insertBlock(
      index,
      LessonHeadingBlock(level: level, children: children),
    );
  }

  LessonDocument insertBulletList(int index, List<LessonListItem> items) {
    return insertBlock(index, LessonListBlock.bullet(items: items));
  }

  LessonDocument insertOrderedList(
    int index,
    List<LessonListItem> items, {
    int start = 1,
  }) {
    return insertBlock(
      index,
      LessonListBlock.ordered(items: items, start: start),
    );
  }

  LessonDocument insertMedia(
    int index, {
    required String mediaType,
    required String lessonMediaId,
  }) {
    return insertBlock(
      index,
      LessonMediaBlock(mediaType: mediaType, lessonMediaId: lessonMediaId),
    );
  }

  LessonDocument insertCta(
    int index, {
    required String label,
    required String targetUrl,
  }) {
    return insertBlock(
      index,
      LessonCtaBlock(label: label, targetUrl: targetUrl),
    );
  }

  LessonDocument formatBlockInlineRange(
    int blockIndex, {
    required int start,
    required int end,
    required LessonInlineMark mark,
  }) {
    return _replaceInlineChildren(blockIndex, (children) {
      return _formatRange(children, start: start, end: end, mark: mark);
    });
  }

  LessonDocument clearBlockInlineFormatting(
    int blockIndex, {
    required int start,
    required int end,
  }) {
    return _replaceInlineChildren(blockIndex, (children) {
      return _clearRange(children, start: start, end: end);
    });
  }

  LessonDocument formatListItemInlineRange(
    int blockIndex, {
    required int itemIndex,
    required int start,
    required int end,
    required LessonInlineMark mark,
  }) {
    return _replaceListItemChildren(blockIndex, itemIndex, (children) {
      return _formatRange(children, start: start, end: end, mark: mark);
    });
  }

  LessonDocument clearListItemInlineFormatting(
    int blockIndex, {
    required int itemIndex,
    required int start,
    required int end,
  }) {
    return _replaceListItemChildren(blockIndex, itemIndex, (children) {
      return _clearRange(children, start: start, end: end);
    });
  }

  LessonDocument validate({Map<String, String>? mediaTypesByLessonMediaId}) {
    LessonDocument.fromJson(
      toJson(),
      mediaTypesByLessonMediaId: mediaTypesByLessonMediaId,
    );
    return this;
  }

  LessonDocument _replaceInlineChildren(
    int blockIndex,
    List<LessonTextRun> Function(List<LessonTextRun>) transform,
  ) {
    final block = blocks[blockIndex];
    final next = [...blocks];
    if (block is LessonParagraphBlock) {
      next[blockIndex] = block.copyWith(children: transform(block.children));
    } else if (block is LessonHeadingBlock) {
      next[blockIndex] = block.copyWith(children: transform(block.children));
    } else {
      throw StateError(
        'Block at index $blockIndex does not contain inline text.',
      );
    }
    return LessonDocument(blocks: List<LessonBlock>.unmodifiable(next));
  }

  LessonDocument _replaceListItemChildren(
    int blockIndex,
    int itemIndex,
    List<LessonTextRun> Function(List<LessonTextRun>) transform,
  ) {
    final block = blocks[blockIndex];
    if (block is! LessonListBlock) {
      throw StateError('Block at index $blockIndex is not a list.');
    }
    final nextItems = [...block.items];
    final item = nextItems[itemIndex];
    nextItems[itemIndex] = item.copyWith(children: transform(item.children));
    final next = [...blocks]..[blockIndex] = block.copyWith(items: nextItems);
    return LessonDocument(blocks: List<LessonBlock>.unmodifiable(next));
  }

  static LessonDocument empty() => const LessonDocument();

  static LessonDocument fromJson(
    Object? payload, {
    Map<String, String>? mediaTypesByLessonMediaId,
  }) {
    if (payload is! Map) {
      throw const FormatException('Lesson document must be a JSON object');
    }
    final map = Map<String, Object?>.from(payload);
    _requireExactKeys(map, {'schema_version', 'blocks'}, 'document');
    if (map['schema_version'] != lessonDocumentSchemaVersion) {
      throw const FormatException('Unsupported lesson document schema_version');
    }
    final blocks = _requiredList(
      map['blocks'],
      'document.blocks',
    ).map(LessonBlock.fromJson).toList(growable: false);
    final document = LessonDocument(
      blocks: List<LessonBlock>.unmodifiable(blocks),
    );
    if (mediaTypesByLessonMediaId != null) {
      document._validateMediaReferences(mediaTypesByLessonMediaId);
    }
    return document;
  }

  void _validateMediaReferences(Map<String, String> mediaTypesByLessonMediaId) {
    for (final block in blocks) {
      if (block is! LessonMediaBlock) {
        continue;
      }
      final expected = mediaTypesByLessonMediaId[block.lessonMediaId];
      if (expected == null) {
        throw FormatException(
          'Media ${block.lessonMediaId} does not belong to this lesson.',
        );
      }
      if (expected != block.mediaType) {
        throw FormatException(
          'Media ${block.lessonMediaId} has type $expected, expected ${block.mediaType}.',
        );
      }
    }
  }
}

List<LessonTextRun> _formatRange(
  List<LessonTextRun> children, {
  required int start,
  required int end,
  required LessonInlineMark mark,
}) {
  _validateRange(children, start: start, end: end);
  return _mapRange(
    children,
    start: start,
    end: end,
    transform: (run) {
      final nextMarks = [...run.marks];
      nextMarks.removeWhere((existing) => existing.type == mark.type);
      nextMarks.add(mark);
      _validateNoDuplicateMarks(nextMarks, 'marks');
      return run.copyWith(
        marks: List<LessonInlineMark>.unmodifiable(nextMarks),
      );
    },
  );
}

List<LessonTextRun> _clearRange(
  List<LessonTextRun> children, {
  required int start,
  required int end,
}) {
  _validateRange(children, start: start, end: end);
  return _mapRange(
    children,
    start: start,
    end: end,
    transform: (run) {
      return run.copyWith(marks: const <LessonInlineMark>[]);
    },
  );
}

List<LessonTextRun> _mapRange(
  List<LessonTextRun> children, {
  required int start,
  required int end,
  required LessonTextRun Function(LessonTextRun run) transform,
}) {
  final output = <LessonTextRun>[];
  var offset = 0;
  for (final run in children) {
    final runStart = offset;
    final runEnd = offset + run.text.length;
    offset = runEnd;

    if (end <= runStart || start >= runEnd) {
      output.add(run);
      continue;
    }

    final localStart = start <= runStart ? 0 : start - runStart;
    final localEnd = end >= runEnd ? run.text.length : end - runStart;
    if (localStart > 0) {
      output.add(run.copyWith(text: run.text.substring(0, localStart)));
    }
    output.add(
      transform(run.copyWith(text: run.text.substring(localStart, localEnd))),
    );
    if (localEnd < run.text.length) {
      output.add(run.copyWith(text: run.text.substring(localEnd)));
    }
  }
  return _mergeAdjacentRuns(output);
}

List<LessonTextRun> _mergeAdjacentRuns(List<LessonTextRun> runs) {
  final merged = <LessonTextRun>[];
  for (final run in runs) {
    if (run.text.isEmpty) {
      continue;
    }
    if (merged.isNotEmpty && _sameMarks(merged.last.marks, run.marks)) {
      final previous = merged.removeLast();
      merged.add(previous.copyWith(text: '${previous.text}${run.text}'));
    } else {
      merged.add(run);
    }
  }
  return List<LessonTextRun>.unmodifiable(merged);
}

bool _sameMarks(List<LessonInlineMark> left, List<LessonInlineMark> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (jsonEncode(left[index].toJson()) != jsonEncode(right[index].toJson())) {
      return false;
    }
  }
  return true;
}

void _validateRange(
  List<LessonTextRun> children, {
  required int start,
  required int end,
}) {
  final length = children.fold<int>(0, (total, run) => total + run.text.length);
  if (start < 0 || end < start || end > length) {
    throw RangeError.range(end, start, length, 'end');
  }
}

List<LessonTextRun> _textRuns(Object? payload, String path) {
  return _requiredList(
    payload,
    path,
  ).map(LessonTextRun.fromJson).toList(growable: false);
}

List<LessonListItem> _listItems(Object? payload, String path) {
  final items = _requiredList(payload, path);
  if (items.isEmpty) {
    throw FormatException('$path must be non-empty.');
  }
  return items.map(LessonListItem.fromJson).toList(growable: false);
}

List<Object?> _requiredList(Object? payload, String path) {
  if (payload is! List) {
    throw FormatException('$path must be a list.');
  }
  return payload.cast<Object?>();
}

String _requiredString(Map<String, Object?> map, String key, String path) {
  final value = map[key];
  if (value is! String) {
    throw FormatException('$path.$key must be a string.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> map, String key, String path) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$path.$key must be a non-empty string.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> map, String key, String path) {
  final value = map[key];
  if (value is! int) {
    throw FormatException('$path.$key must be an integer.');
  }
  return value;
}

void _requireExactKeys(
  Map<String, Object?> map,
  Set<String> allowed,
  String path,
) {
  final keys = map.keys.toSet();
  final required = allowed.difference({'id', 'marks', 'start'});
  final missing = required.difference(keys);
  final unknown = keys.difference(allowed);
  if (missing.isNotEmpty) {
    throw FormatException('$path is missing ${missing.join(', ')}.');
  }
  if (unknown.isNotEmpty) {
    throw FormatException('$path has unsupported keys ${unknown.join(', ')}.');
  }
}

void _validateNoDuplicateMarks(List<LessonInlineMark> marks, String path) {
  final seen = <String>{};
  for (final mark in marks) {
    if (!seen.add(mark.type)) {
      throw FormatException('$path duplicates ${mark.type}.');
    }
  }
}

void _validateTargetUrl(String value, String path) {
  final target = value.trim();
  if (target.isEmpty) {
    throw FormatException('$path must not be blank.');
  }
  final uri = Uri.tryParse(target);
  if (uri == null) {
    throw FormatException('$path must be a URL.');
  }
  if (uri.hasScheme) {
    if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      throw FormatException('$path must be http(s).');
    }
    return;
  }
  if (target.startsWith('/') && !target.startsWith('//')) {
    return;
  }
  throw FormatException('$path must be absolute http(s) or root-relative.');
}

Object? _deepSort(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _deepSort(value[key])};
  }
  if (value is List) {
    return value.map(_deepSort).toList(growable: false);
  }
  return value;
}
