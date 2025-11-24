import 'package:flutter/material.dart';

/// Minimal JSON-DSL renderer for experimental AI-driven UIs.
///
/// Schema (informal):
/// { "type": "column"|"row"|"text"|"button"|"spacer"|"card",
///   "props": { ... },
///   "children": [ ... ] }
class GeminiClient {
  const GeminiClient();

  /// Render a widget tree from a JSON-like map.
  static Widget render(
    Map<String, dynamic> node, {
    void Function(String action, Map<String, dynamic>? payload)? onAction,
  }) {
    final type = (node['type'] as String?)?.toLowerCase() ?? 'column';
    final props = (node['props'] as Map?)?.cast<String, dynamic>() ?? const {};
    final children = (node['children'] as List?)?.cast<Map>() ?? const [];
    switch (type) {
      case 'text':
        return Text(
          (props['text'] as String?) ?? '',
          textAlign: _parseAlign(props['align']),
          style: _parseTextStyle(props['style'] as Map<String, dynamic>?),
        );
      case 'button':
        return ElevatedButton(
          onPressed: () => onAction?.call(
            props['action'] as String? ?? 'tap',
            (props['payload'] as Map?)?.cast<String, dynamic>(),
          ),
          child: Text((props['label'] as String?) ?? 'OK'),
        );
      case 'spacer':
        return SizedBox(
          height: _toDouble(props['height'], 8),
          width: _toDouble(props['width'], 8),
        );
      case 'row':
        return Row(
          mainAxisAlignment: _parseMain(props['mainAxis'] as String?),
          crossAxisAlignment: _parseCross(props['crossAxis'] as String?),
          children: [
            for (final c in children)
              render(c.cast<String, dynamic>(), onAction: onAction),
          ],
        );
      case 'card':
        return Card(
          child: Padding(
            padding: EdgeInsets.all(_toDouble(props['padding'], 12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in children)
                  render(c.cast<String, dynamic>(), onAction: onAction),
              ],
            ),
          ),
        );
      case 'column':
      default:
        return Column(
          crossAxisAlignment: _parseCross(props['crossAxis'] as String?),
          mainAxisAlignment: _parseMain(props['mainAxis'] as String?),
          children: [
            for (final c in children)
              render(c.cast<String, dynamic>(), onAction: onAction),
          ],
        );
    }
  }

  static TextAlign _parseAlign(dynamic v) {
    switch (v) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.left;
    }
  }

  static MainAxisAlignment _parseMain(String? v) {
    switch (v) {
      case 'center':
        return MainAxisAlignment.center;
      case 'end':
        return MainAxisAlignment.end;
      case 'spaceBetween':
        return MainAxisAlignment.spaceBetween;
      default:
        return MainAxisAlignment.start;
    }
  }

  static CrossAxisAlignment _parseCross(String? v) {
    switch (v) {
      case 'center':
        return CrossAxisAlignment.center;
      case 'end':
        return CrossAxisAlignment.end;
      default:
        return CrossAxisAlignment.start;
    }
  }

  static TextStyle? _parseTextStyle(Map<String, dynamic>? m) {
    if (m == null) return null;
    return TextStyle(
      fontSize: _toDouble(m['size'], null),
      fontWeight: _toWeight(m['weight'] as String?),
    );
  }

  static FontWeight? _toWeight(String? v) {
    switch (v) {
      case 'w600':
        return FontWeight.w600;
      case 'w700':
        return FontWeight.w700;
      case 'w800':
        return FontWeight.w800;
      case 'bold':
        return FontWeight.bold;
      default:
        return null;
    }
  }

  static double _toDouble(dynamic v, double? fallback) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? (fallback ?? 0);
    return fallback ?? 0;
  }
}
