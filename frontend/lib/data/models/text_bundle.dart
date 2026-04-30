import 'package:flutter/foundation.dart';

@immutable
class TextNode {
  const TextNode({required this.value});

  final String value;

  factory TextNode.fromResponse(Object? payload, String textId) {
    if (payload is String) {
      return TextNode(value: _requiredValue(payload, textId));
    }
    if (payload is Map) {
      final value = payload['value'];
      if (value is String) {
        return TextNode(value: _requiredValue(value, textId));
      }
    }
    throw StateError('Invalid text bundle value for $textId');
  }

  static String _requiredValue(String value, String textId) {
    if (value.isEmpty) {
      throw StateError('Empty text bundle value for $textId');
    }
    return value;
  }
}

@immutable
class TextBundle {
  const TextBundle({
    required this.bundleId,
    required this.locale,
    required this.version,
    required this.hash,
    required this.texts,
  });

  final String bundleId;
  final String locale;
  final String version;
  final String hash;
  final Map<String, TextNode> texts;

  factory TextBundle.fromResponse(Object? payload) {
    if (payload is! Map) {
      throw StateError('Text bundle payload must be an object');
    }
    final textsPayload = _requiredBundleField(payload, 'texts');
    if (textsPayload is! Map) {
      throw StateError('Text bundle texts must be an object');
    }

    final texts = <String, TextNode>{};
    for (final entry in textsPayload.entries) {
      final key = entry.key;
      if (key is! String || key.isEmpty) {
        throw StateError('Text bundle contains an invalid text_id');
      }
      texts[key] = TextNode.fromResponse(entry.value, key);
    }
    if (texts.isEmpty) {
      throw StateError('Text bundle texts must not be empty');
    }

    return TextBundle(
      bundleId: _requiredBundleString(payload, 'bundle_id'),
      locale: _requiredBundleString(payload, 'locale'),
      version: _requiredBundleString(payload, 'version'),
      hash: _requiredBundleString(payload, 'hash'),
      texts: Map<String, TextNode>.unmodifiable(texts),
    );
  }
}

List<TextBundle> parseTextBundles(Object? payload, {required String label}) {
  if (payload is! List) {
    throw StateError('$label text_bundles must be a list');
  }
  final seen = <String>{};
  final bundles = <TextBundle>[];
  for (final item in payload) {
    final bundle = TextBundle.fromResponse(item);
    final identity = '${bundle.bundleId}:${bundle.locale}';
    if (!seen.add(identity)) {
      throw StateError('$label contains duplicate text bundle: $identity');
    }
    bundles.add(bundle);
  }
  if (bundles.isEmpty) {
    throw StateError('$label text_bundles must not be empty');
  }
  return List<TextBundle>.unmodifiable(bundles);
}

String resolveText(String textId, List<TextBundle> textBundles) {
  if (textId.isEmpty) {
    throw StateError('CTA text_id is missing');
  }
  if (textBundles.isEmpty) {
    throw StateError('CTA text bundle is missing for $textId');
  }

  TextNode? resolved;
  for (final bundle in textBundles) {
    final node = bundle.texts[textId];
    if (node == null) {
      continue;
    }
    if (resolved != null) {
      throw StateError('CTA text_id is duplicated across bundles: $textId');
    }
    resolved = node;
  }

  final value = resolved?.value;
  if (value == null) {
    throw StateError('CTA text_id has no bundle value: $textId');
  }
  if (value.isEmpty) {
    throw StateError('CTA text_id resolved to an empty value: $textId');
  }
  return value;
}

Object? _requiredBundleField(Map<dynamic, dynamic> payload, String key) {
  if (!payload.containsKey(key)) {
    throw StateError('Text bundle is missing required field: $key');
  }
  return payload[key];
}

String _requiredBundleString(Map<dynamic, dynamic> payload, String key) {
  final value = _requiredBundleField(payload, key);
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw StateError('Text bundle field "$key" must be a non-empty string');
}
