import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;

const Set<String> _blockAttributeKeys = <String>{'header', 'list', 'indent'};

bool styleHasInlineAttributesForLiveNewlineSanitization(quill.Style style) {
  return style.attributes.values.any(
    (attribute) => attribute.scope != quill.AttributeScope.block,
  );
}

quill.Style stripInlineAttributesForLiveNewlineSanitization(quill.Style style) {
  return quill.Style.attr(
    Map<String, quill.Attribute>.fromEntries(
      style.attributes.entries.where(
        (entry) => entry.value.scope == quill.AttributeScope.block,
      ),
    ),
  );
}

quill_delta.Delta normalizeDeltaForGuard(quill_delta.Delta source) {
  final normalizedOperations = <_NormalizedInsertOperation>[];

  void pushInsert(Object value, Map<String, dynamic>? attributes) {
    if (value is String && value.isEmpty) {
      return;
    }

    final normalizedAttributes = _normalizeAttributes(attributes);
    if (value is String &&
        value != '\n' &&
        normalizedOperations.isNotEmpty &&
        normalizedOperations.last.value is String &&
        normalizedOperations.last.value != '\n' &&
        _stableAttributes(normalizedOperations.last.attributes) ==
            _stableAttributes(normalizedAttributes)) {
      final previous = normalizedOperations.removeLast();
      normalizedOperations.add(
        _NormalizedInsertOperation(
          value: '${previous.value as String}$value',
          attributes: normalizedAttributes,
        ),
      );
      return;
    }

    normalizedOperations.add(
      _NormalizedInsertOperation(
        value: value,
        attributes: normalizedAttributes,
      ),
    );
  }

  void pushStringInsert(String value, Map<String, dynamic>? attributes) {
    if (value.isEmpty) {
      return;
    }

    var buffer = StringBuffer();
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      if (character == '\n') {
        if (buffer.isNotEmpty) {
          pushInsert(buffer.toString(), _textAttributes(attributes));
          buffer = StringBuffer();
        }
        pushInsert('\n', _newlineAttributes(attributes));
        continue;
      }
      buffer.write(character);
    }

    if (buffer.isNotEmpty) {
      pushInsert(buffer.toString(), _textAttributes(attributes));
    }
  }

  for (final operation in source.toList()) {
    if (!operation.isInsert) {
      continue;
    }

    final value = operation.value;
    final attributes = operation.attributes == null
        ? null
        : Map<String, dynamic>.from(operation.attributes!);

    if (value is! String) {
      pushInsert(value, attributes);
      continue;
    }

    pushStringInsert(value, attributes);
  }

  while (normalizedOperations.isNotEmpty) {
    final last = normalizedOperations.last;
    final value = last.value;
    if (value is! String || !value.contains('\n') || value == '\n') {
      break;
    }
    normalizedOperations.removeLast();
    pushStringInsert(value, last.attributes);
  }

  if (normalizedOperations.isEmpty) {
    return quill_delta.Delta()..insert('\n');
  }

  final last = normalizedOperations.last;
  if (last.value == '\n') {
    normalizedOperations[normalizedOperations.length -
        1] = _NormalizedInsertOperation(
      value: '\n',
      attributes: _newlineAttributes(last.attributes),
    );
  } else {
    normalizedOperations.add(const _NormalizedInsertOperation(value: '\n'));
  }

  final normalized = quill_delta.Delta();
  for (final operation in normalizedOperations) {
    normalized.insert(operation.value, operation.attributes);
  }
  return normalized;
}

Map<String, dynamic>? _normalizeAttributes(Map<String, dynamic>? attributes) {
  if (attributes == null || attributes.isEmpty) {
    return null;
  }

  final normalized = <String, dynamic>{};
  for (final entry in attributes.entries) {
    final value = entry.value;
    if (value == null || value == false) {
      continue;
    }
    normalized[entry.key] = value;
  }

  return normalized.isEmpty ? null : normalized;
}

Map<String, dynamic>? _textAttributes(Map<String, dynamic>? attributes) {
  final normalized = _normalizeAttributes(attributes);
  if (normalized == null) {
    return null;
  }

  final textAttributes = <String, dynamic>{};
  for (final entry in normalized.entries) {
    if (_blockAttributeKeys.contains(entry.key)) {
      continue;
    }
    textAttributes[entry.key] = entry.value;
  }

  return textAttributes.isEmpty ? null : textAttributes;
}

Map<String, dynamic>? _newlineAttributes(Map<String, dynamic>? attributes) {
  final normalized = _normalizeAttributes(attributes);
  if (normalized == null) {
    return null;
  }

  final newlineAttributes = <String, dynamic>{};
  for (final entry in normalized.entries) {
    if (!_blockAttributeKeys.contains(entry.key)) {
      continue;
    }
    newlineAttributes[entry.key] = entry.value;
  }

  return newlineAttributes.isEmpty ? null : newlineAttributes;
}

String _stableAttributes(Map<String, dynamic>? attributes) {
  if (attributes == null || attributes.isEmpty) {
    return '';
  }

  final sorted = Map<String, dynamic>.fromEntries(
    attributes.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key)),
  );
  return jsonEncode(sorted);
}

class _NormalizedInsertOperation {
  const _NormalizedInsertOperation({required this.value, this.attributes});

  final Object value;
  final Map<String, dynamic>? attributes;
}
