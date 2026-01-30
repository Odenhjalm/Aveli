import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_quill/markdown_quill.dart';

import 'package:aveli/features/media/data/media_repository.dart';

/// Lesson content is stored as Markdown (`content_markdown`), but when media is
/// resized in the Studio editor we serialize embeds as HTML tags (e.g.
/// `<img ... />`) to preserve width/height/style attributes.
///
/// To avoid inconsistencies (like raw `<img>` leaking as visible text), both
/// Studio and lesson presentation must use this single Markdown ↔ Delta
/// conversion pipeline.

class AudioBlockEmbed extends quill.CustomBlockEmbed {
  static const String embedType = 'audio';

  const AudioBlockEmbed(String data) : super(embedType, data);

  static AudioBlockEmbed fromUrl(String url) => AudioBlockEmbed(url);
}

const HtmlEscape _htmlAttributeEscape = HtmlEscape(HtmlEscapeMode.attribute);

@visibleForTesting
String? lessonMediaUrlFromEmbedValue(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (value is Map) {
    for (final key in const ['source', 'src', 'url', 'download_url']) {
      final dynamic nested = value[key];
      if (nested is String && nested.trim().isNotEmpty) {
        return nested.trim();
      }
    }
  }
  return null;
}

String _normalizeMediaSourceAttribute(Map<String, String> attrs) {
  for (final key in const [
    'src',
    'data-src',
    'data-url',
    'data-download-url',
  ]) {
    final value = attrs[key];
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return '';
}

@visibleForTesting
DeltaToMarkdown createLessonDeltaToMarkdown() {
  return DeltaToMarkdown(
    customEmbedHandlers: {
      AudioBlockEmbed.embedType: (embed, out) {
        final url = lessonMediaUrlFromEmbedValue(embed.value.data);
        if (url == null || url.isEmpty) return;
        final escaped = _htmlAttributeEscape.convert(url);
        out.write('<audio controls src="$escaped"></audio>');
      },
      quill.BlockEmbed.imageType: (embed, out) {
        final url = lessonMediaUrlFromEmbedValue(embed.value.data);
        if (url == null || url.isEmpty) return;

        final styleValue =
            embed.style.attributes[quill.Attribute.style.key]?.value;
        final widthValue =
            embed.style.attributes[quill.Attribute.width.key]?.value;
        final heightValue =
            embed.style.attributes[quill.Attribute.height.key]?.value;

        final style =
            (styleValue is String ? styleValue : styleValue?.toString() ?? '')
                .trim();
        final width =
            (widthValue is String ? widthValue : widthValue?.toString() ?? '')
                .trim();
        final height =
            (heightValue is String
                    ? heightValue
                    : heightValue?.toString() ?? '')
                .trim();

        if (style.isEmpty && width.isEmpty && height.isEmpty) {
          out.write('![]($url)');
          return;
        }

        final escaped = _htmlAttributeEscape.convert(url);
        out.write('<img src="$escaped"');
        if (style.isNotEmpty) {
          out.write(' style="${_htmlAttributeEscape.convert(style)}"');
        }
        if (width.isNotEmpty) {
          out.write(' width="${_htmlAttributeEscape.convert(width)}"');
        }
        if (height.isNotEmpty) {
          out.write(' height="${_htmlAttributeEscape.convert(height)}"');
        }
        out.write(' />');
      },
      quill.BlockEmbed.videoType: (embed, out) {
        final url = lessonMediaUrlFromEmbedValue(embed.value.data);
        if (url == null || url.isEmpty) return;
        final escaped = _htmlAttributeEscape.convert(url);
        out.write('<video controls src="$escaped"></video>');
      },
    },
  );
}

@visibleForTesting
MarkdownToDelta createLessonMarkdownToDelta(md.Document markdownDocument) {
  return MarkdownToDelta(
    markdownDocument: markdownDocument,
    customElementToEmbeddable: {
      'audio': (attrs) =>
          AudioBlockEmbed.fromUrl(_normalizeMediaSourceAttribute(attrs)),
      'video': (attrs) =>
          quill.BlockEmbed.video(_normalizeMediaSourceAttribute(attrs)),
    },
  );
}

final RegExp _audioHtmlTagPattern = RegExp(
  r'''<audio\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*></audio>''',
  caseSensitive: false,
);

final RegExp _videoHtmlTagPattern = RegExp(
  r'''<video\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*></video>''',
  caseSensitive: false,
);

final RegExp _imgHtmlTagPattern = RegExp(
  r'''<img\b[^>]*?>''',
  caseSensitive: false,
);

final RegExp _htmlAttributePattern = RegExp(
  r'''([a-zA-Z_:][a-zA-Z0-9_\-:.]*)\s*=\s*("([^"]*)"|'([^']*)')''',
);

Map<String, String> _parseHtmlAttributes(String html) {
  final attributes = <String, String>{};
  for (final match in _htmlAttributePattern.allMatches(html)) {
    final key = match.group(1);
    if (key == null || key.isEmpty) continue;
    final value = match.group(3) ?? match.group(4) ?? '';
    attributes[key.toLowerCase()] = value;
  }
  return attributes;
}

quill_delta.Delta _replaceHtmlTagWithEmbed(
  quill_delta.Delta source,
  RegExp pattern,
  dynamic Function(String url) embedFactory,
) {
  final result = quill_delta.Delta();
  for (final operation in source.toList()) {
    if (!operation.isInsert) {
      result.push(operation);
      continue;
    }
    final value = operation.value;
    if (value is! String) {
      result.push(operation);
      continue;
    }
    final matches = pattern.allMatches(value).toList();
    if (matches.isEmpty) {
      result.insert(value, operation.attributes);
      continue;
    }
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        final chunk = value.substring(cursor, match.start);
        if (chunk.isNotEmpty) {
          result.insert(chunk, operation.attributes);
        }
      }
      final url = match.group(1);
      if (url != null && url.trim().isNotEmpty) {
        result.insert(embedFactory(url.trim()), operation.attributes);
      } else {
        final raw = match.group(0) ?? '';
        if (raw.isNotEmpty) {
          result.insert(raw, operation.attributes);
        }
      }
      cursor = match.end;
    }
    if (cursor < value.length) {
      final remainder = value.substring(cursor);
      if (remainder.isNotEmpty) {
        result.insert(remainder, operation.attributes);
      }
    }
  }
  return result;
}

quill_delta.Delta _replaceHtmlImgTagsWithEmbeds(quill_delta.Delta source) {
  final result = quill_delta.Delta();
  for (final operation in source.toList()) {
    if (!operation.isInsert) {
      result.push(operation);
      continue;
    }
    final value = operation.value;
    if (value is! String) {
      result.push(operation);
      continue;
    }

    final matches = _imgHtmlTagPattern.allMatches(value).toList();
    if (matches.isEmpty) {
      result.insert(value, operation.attributes);
      continue;
    }

    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        final chunk = value.substring(cursor, match.start);
        if (chunk.isNotEmpty) {
          result.insert(chunk, operation.attributes);
        }
      }

      final raw = match.group(0) ?? '';
      final attrs = _parseHtmlAttributes(raw);
      final src = _normalizeMediaSourceAttribute(attrs);
      if (src.isEmpty) {
        if (raw.isNotEmpty) {
          result.insert(raw, operation.attributes);
        }
      } else {
        final mergedAttrs = operation.attributes == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(operation.attributes!);

        final style = attrs['style'];
        if (style != null && style.trim().isNotEmpty) {
          mergedAttrs[quill.Attribute.style.key] = style.trim();
        }
        final width = attrs['width'];
        if (width != null && width.trim().isNotEmpty) {
          mergedAttrs[quill.Attribute.width.key] = width.trim();
        }
        final height = attrs['height'];
        if (height != null && height.trim().isNotEmpty) {
          mergedAttrs[quill.Attribute.height.key] = height.trim();
        }

        result.insert(
          quill.BlockEmbed.image(src),
          mergedAttrs.isEmpty ? null : mergedAttrs,
        );
      }

      cursor = match.end;
    }

    if (cursor < value.length) {
      final remainder = value.substring(cursor);
      if (remainder.isNotEmpty) {
        result.insert(remainder, operation.attributes);
      }
    }
  }
  return result;
}

@visibleForTesting
quill_delta.Delta convertLessonMarkdownToDelta(
  MarkdownToDelta converter,
  String markdown,
) {
  final converted = converter.convert(markdown);
  final withAudio = _replaceHtmlTagWithEmbed(
    converted,
    _audioHtmlTagPattern,
    (url) => AudioBlockEmbed.fromUrl(url),
  );
  final withVideo = _replaceHtmlTagWithEmbed(
    withAudio,
    _videoHtmlTagPattern,
    (url) => quill.BlockEmbed.video(url),
  );
  final withImages = _replaceHtmlImgTagsWithEmbeds(withVideo);
  return withImages;
}

final RegExp studioMediaUrlPattern = RegExp(
  r'''(?:https?:\/\/[^\s"'()]+)?\/studio\/media\/([0-9a-fA-F-]{36})''',
  caseSensitive: false,
);

final RegExp mediaStreamUrlPattern = RegExp(
  r'''(?:https?:\/\/[^\s"'()]+)?\/media\/stream\/([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)''',
);

String? _extractMediaIdFromToken(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payloadRaw = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final jsonValue = json.decode(payloadRaw);
    if (jsonValue is! Map<String, dynamic>) return null;
    final sub = jsonValue['sub'];
    return sub is String && sub.isNotEmpty ? sub : null;
  } catch (_) {
    return null;
  }
}

Set<String> extractLessonEmbeddedMediaIds(String markdown) {
  final ids = <String>{};
  for (final match in studioMediaUrlPattern.allMatches(markdown)) {
    final id = match.group(1);
    if (id != null && id.isNotEmpty) {
      ids.add(id);
    }
  }
  for (final match in mediaStreamUrlPattern.allMatches(markdown)) {
    final token = match.group(1);
    if (token == null || token.isEmpty) continue;
    final id = _extractMediaIdFromToken(token);
    if (id != null && id.isNotEmpty) {
      ids.add(id);
    }
  }
  return ids;
}

Future<String> prepareLessonMarkdownForRendering(
  MediaRepository mediaRepository,
  String markdown,
) async {
  if (markdown.trim().isEmpty) return markdown;

  final ids = extractLessonEmbeddedMediaIds(markdown);
  if (ids.isEmpty) return markdown;

  final signedUrls = <String, String>{};
  for (final id in ids) {
    try {
      final signed = await mediaRepository.signMedia(id);
      try {
        signedUrls[id] = mediaRepository.resolveUrl(signed.signedUrl);
      } catch (_) {
        signedUrls[id] = signed.signedUrl;
      }
    } catch (_) {}
  }
  if (signedUrls.isEmpty) return markdown;

  var resolved = markdown;
  resolved = resolved.replaceAllMapped(studioMediaUrlPattern, (match) {
    final id = match.group(1);
    if (id == null || id.isEmpty) return match.group(0) ?? '';
    return signedUrls[id] ?? (match.group(0) ?? '');
  });
  resolved = resolved.replaceAllMapped(mediaStreamUrlPattern, (match) {
    final token = match.group(1);
    if (token == null || token.isEmpty) return match.group(0) ?? '';
    final id = _extractMediaIdFromToken(token);
    if (id == null || id.isEmpty) return match.group(0) ?? '';
    return signedUrls[id] ?? (match.group(0) ?? '');
  });
  return resolved;
}

@visibleForTesting
String normalizeLessonMarkdownForStorage(String markdown) {
  if (markdown.isEmpty) return markdown;

  var normalized = markdown;
  normalized = normalized.replaceAllMapped(studioMediaUrlPattern, (match) {
    final id = match.group(1);
    if (id == null || id.isEmpty) return match.group(0) ?? '';
    return '/studio/media/$id';
  });
  normalized = normalized.replaceAllMapped(mediaStreamUrlPattern, (match) {
    final token = match.group(1);
    if (token == null || token.isEmpty) return match.group(0) ?? '';
    final id = _extractMediaIdFromToken(token);
    if (id == null || id.isEmpty) return match.group(0) ?? '';
    return '/studio/media/$id';
  });
  return normalized;
}

