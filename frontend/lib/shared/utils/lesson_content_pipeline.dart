import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_quill/markdown_quill.dart';

import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_repository.dart';

/// Lesson content is stored as canonical Markdown (`content_markdown`).
///
/// Lesson media persists as canonical tokens (`!image(id)`, `!audio(id)`,
/// `!video(id)`, `!document(id)`) while the editor continues to use Quill
/// Delta internally.
/// Legacy HTML media is accepted on import/render only so both Studio and
/// lesson presentation can share this single Markdown ↔ Delta pipeline.
/// Storage writes remain strict: only typed lesson_media tokens are allowed.

class AudioBlockEmbed extends quill.CustomBlockEmbed {
  static const String embedType = 'audio';

  const AudioBlockEmbed(String data) : super(embedType, data);

  static AudioBlockEmbed fromUrl(String url) => AudioBlockEmbed(url);

  /// Stable embed marker for lesson media audio.
  static AudioBlockEmbed fromLessonMedia({required String lessonMediaId}) =>
      AudioBlockEmbed(
        jsonEncode(<String, dynamic>{
          'lesson_media_id': lessonMediaId,
          'kind': 'audio',
        }),
      );
}

String videoBlockEmbedValueFromLessonMedia({required String lessonMediaId}) =>
    jsonEncode(<String, dynamic>{
      'lesson_media_id': lessonMediaId,
      'kind': 'video',
    });

String imageBlockEmbedValueFromLessonMedia({
  required String lessonMediaId,
  String? alt,
}) => jsonEncode(<String, dynamic>{
  'lesson_media_id': lessonMediaId,
  'kind': 'image',
  if (alt != null && alt.trim().isNotEmpty) 'alt': alt.trim(),
});

const HtmlEscape _htmlAttributeEscape = HtmlEscape(HtmlEscapeMode.attribute);

String? lessonMediaUrlFromEmbedValue(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    final trimmed = value.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = json.decode(trimmed);
        if (decoded is Map) {
          final lessonMediaId = decoded['lesson_media_id'];
          if (lessonMediaId is String && lessonMediaId.trim().isNotEmpty) {
            return null;
          }
          for (final key in const ['source', 'src', 'url', 'download_url']) {
            final dynamic nested = decoded[key];
            if (nested is String && nested.trim().isNotEmpty) {
              return nested.trim();
            }
          }
        }
      } catch (_) {
        // Not JSON – fall through.
      }
    }
    return trimmed;
  }
  if (value is Map) {
    final lessonMediaId = value['lesson_media_id'];
    if (lessonMediaId is String && lessonMediaId.trim().isNotEmpty) {
      return null;
    }
    for (final key in const ['source', 'src', 'url', 'download_url']) {
      final dynamic nested = value[key];
      if (nested is String && nested.trim().isNotEmpty) {
        return nested.trim();
      }
    }
  }
  return null;
}

String? _lessonMediaIdFromEmbedValue(dynamic value) {
  if (value is Map) {
    final raw = value['lesson_media_id'] ?? value['lessonMediaId'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  }

  if (value is String && value.trim().isNotEmpty) {
    final trimmed = value.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = json.decode(trimmed);
        if (decoded is Map) {
          final raw = decoded['lesson_media_id'] ?? decoded['lessonMediaId'];
          if (raw is String && raw.trim().isNotEmpty) return raw.trim();
        }
      } catch (_) {}
    }
  }

  return null;
}

String? lessonMediaIdFromEmbedValue(dynamic value) =>
    _lessonMediaIdFromEmbedValue(value);

String? rawLessonMediaSourceFromEmbedValue(dynamic value) {
  final explicitUrl = lessonMediaUrlFromEmbedValue(value);
  if (explicitUrl != null && explicitUrl.isNotEmpty) {
    return explicitUrl;
  }
  final lessonMediaId = lessonMediaIdFromEmbedValue(value);
  if (lessonMediaId != null && lessonMediaId.isNotEmpty) {
    return null;
  }
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

String? lessonMediaAltFromEmbedValue(dynamic value) {
  if (value is Map) {
    final raw = value['alt'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  }

  if (value is String && value.trim().isNotEmpty) {
    final trimmed = value.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = json.decode(trimmed);
        if (decoded is Map) {
          final raw = decoded['alt'];
          if (raw is String && raw.trim().isNotEmpty) return raw.trim();
        }
      } catch (_) {}
    }
  }

  return null;
}

String? normalizeVideoPlaybackUrl(String? rawValue) {
  final trimmed = rawValue?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return uri.toString();
}

bool _isStudioMediaUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final uri = Uri.tryParse(trimmed);
  final path = uri?.path ?? trimmed;
  final normalizedPath = path.toLowerCase();
  if (normalizedPath.startsWith('/studio/media/') ||
      normalizedPath.startsWith('/media/stream/')) {
    return true;
  }
  final normalized = trimmed.toLowerCase();
  return normalized.contains('/studio/media/') ||
      normalized.contains('/media/stream/');
}

/// Legacy video embeds cannot be rendered safely by the current player.
///
/// Detection is intentionally conservative and does not migrate/rewrite the
/// source content. Callers can use this to render placeholders and allow
/// manual replacement in the editor.
bool isLegacyVideoEmbed(dynamic value) {
  final url =
      lessonMediaUrlFromEmbedValue(value) ??
      (value == null ? '' : value.toString());
  final trimmed = url.trim();
  if (trimmed.isEmpty) return true;
  if (_isStudioMediaUrl(trimmed)) return true;
  return normalizeVideoPlaybackUrl(trimmed) == null;
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

String _lessonMediaToken({
  required String kind,
  required String lessonMediaId,
}) => '!$kind($lessonMediaId)';

const String _lessonMediaDocumentLinkScheme = 'aveli-document';

String lessonMediaDocumentLinkUrl(String lessonMediaId) =>
    '$_lessonMediaDocumentLinkScheme://$lessonMediaId';

bool _isInternalLessonMediaDocumentLinkUrl(String? rawUrl) {
  final normalized = rawUrl?.trim();
  if (normalized == null || normalized.isEmpty) {
    return false;
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null) {
    return false;
  }
  return uri.scheme.toLowerCase() == _lessonMediaDocumentLinkScheme;
}

String? lessonMediaIdFromDocumentLinkUrl(String? rawUrl) {
  final normalized = rawUrl?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(normalized);
  if (uri != null &&
      uri.scheme.toLowerCase() == _lessonMediaDocumentLinkScheme) {
    final host = uri.host.trim();
    if (host.isNotEmpty) {
      return host;
    }
    final path = uri.path.replaceAll('/', '').trim();
    if (path.isNotEmpty) {
      return path;
    }
  }

  return null;
}

String _documentLinkLabel({String? rawLabel, String? fileName}) {
  final preferred = rawLabel?.trim();
  final resolved = preferred != null && preferred.isNotEmpty
      ? preferred
      : (fileName?.trim().isNotEmpty == true ? fileName!.trim() : 'Dokument');
  if (resolved.startsWith('📄 ')) {
    return resolved;
  }
  return '📄 $resolved';
}

Never _throwCanonicalMediaWriteViolation(String raw) {
  throw StateError(
    'Canonical text contract violation: media refs must use typed '
    'lesson_media ids. Could not normalize ${raw.trim()}.',
  );
}

DeltaToMarkdown createLessonDeltaToMarkdown() {
  return DeltaToMarkdown(
    customEmbedHandlers: {
      AudioBlockEmbed.embedType: (embed, out) {
        final lessonMediaId = _lessonMediaIdFromEmbedValue(embed.value.data);
        if (lessonMediaId != null && lessonMediaId.isNotEmpty) {
          out.write(
            _lessonMediaToken(kind: 'audio', lessonMediaId: lessonMediaId),
          );
          return;
        }
      },
      quill.BlockEmbed.imageType: (embed, out) {
        final lessonMediaId = _lessonMediaIdFromEmbedValue(embed.value.data);
        if (lessonMediaId != null && lessonMediaId.isNotEmpty) {
          out.write(
            _lessonMediaToken(kind: 'image', lessonMediaId: lessonMediaId),
          );
          return;
        }

        final url = lessonMediaUrlFromEmbedValue(embed.value.data);
        if (url == null || url.isEmpty) return;
        out.write('![]($url)');
      },
      quill.BlockEmbed.videoType: (embed, out) {
        final lessonMediaId = _lessonMediaIdFromEmbedValue(embed.value.data);
        if (lessonMediaId != null && lessonMediaId.isNotEmpty) {
          out.write(
            _lessonMediaToken(kind: 'video', lessonMediaId: lessonMediaId),
          );
          return;
        }
      },
    },
  );
}

MarkdownToDelta createLessonMarkdownToDelta(md.Document markdownDocument) {
  return MarkdownToDelta(
    markdownDocument: markdownDocument,
    customElementToEmbeddable: {
      'audio': (attrs) {
        final src = _normalizeMediaSourceAttribute(attrs);
        final id = _lessonMediaIdFromMediaAttributes(attrs);
        if (id != null && id.isNotEmpty) {
          return AudioBlockEmbed.fromLessonMedia(lessonMediaId: id);
        }
        return AudioBlockEmbed.fromUrl(src);
      },
      'video': (attrs) {
        final src = _normalizeMediaSourceAttribute(attrs);
        final id = _lessonMediaIdFromMediaAttributes(attrs);
        if (id != null && id.isNotEmpty) {
          return quill.BlockEmbed.video(
            videoBlockEmbedValueFromLessonMedia(lessonMediaId: id),
          );
        }
        return quill.BlockEmbed.video(src);
      },
    },
  );
}

const String _lessonMediaIdFragment = r'([A-Za-z0-9_-]+(?:-[A-Za-z0-9_-]+)*)';

final RegExp _audioHtmlElementPattern = RegExp(
  r'''<audio\b[^>]*?(?:\/>|>.*?<\/audio>)''',
  caseSensitive: false,
  dotAll: true,
);

final RegExp _videoHtmlElementPattern = RegExp(
  r'''<video\b[^>]*?(?:\/>|>.*?<\/video>)''',
  caseSensitive: false,
  dotAll: true,
);

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

final RegExp _forbiddenHtmlMediaPattern = RegExp(
  r'<\s*(video|audio|img)\b',
  caseSensitive: false,
);

final RegExp _htmlAttributePattern = RegExp(
  r'''([a-zA-Z_:][a-zA-Z0-9_\-:.]*)\s*=\s*("([^"]*)"|'([^']*)')''',
);

final RegExp _lessonImageTokenPattern = RegExp(
  '!image\\($_lessonMediaIdFragment\\)',
  caseSensitive: false,
);

final RegExp _lessonAudioTokenPattern = RegExp(
  '!audio\\($_lessonMediaIdFragment\\)',
  caseSensitive: false,
);

final RegExp _lessonVideoTokenPattern = RegExp(
  '!video\\($_lessonMediaIdFragment\\)',
  caseSensitive: false,
);

final RegExp _lessonDocumentTokenPattern = RegExp(
  '!document\\($_lessonMediaIdFragment\\)',
  caseSensitive: false,
);

final RegExp _markdownImagePattern = RegExp(
  r'''!\[[^\]]*]\((?:<)?([^)>\s]+)(?:>)?(?:\s+"[^"]*")?\)''',
  caseSensitive: false,
);

final RegExp _markdownLinkPattern = RegExp(
  r'''(?<!!)\[([^\]]*)]\((?:<)?([^)>\s]+)(?:>)?(?:\s+"[^"]*")?\)''',
  caseSensitive: false,
);

// This sentinel preserves empty paragraphs during Markdown → Quill Delta
// round-trip.
//
// Do NOT remove unless replacing the editor or markdown conversion pipeline.
// Removing this will reintroduce the “paragraphs not saved” bug.
const String _blankLineSentinel = '\u200B';
final RegExp _multiNewlinePattern = RegExp(r'\n{4,}');

String _preserveExtraBlankLinesForDelta(String markdown) {
  if (markdown.isEmpty || !markdown.contains('\n\n\n')) return markdown;
  return markdown.replaceAllMapped(_multiNewlinePattern, (match) {
    final run = match.group(0) ?? '';
    if (run.length < 4) return run;

    final pairs = run.length ~/ 2;
    final extraPairs = pairs - 1;

    final out = StringBuffer()..write('\n\n');
    for (var i = 0; i < extraPairs; i++) {
      out.write(_blankLineSentinel);
      out.write('\n\n');
    }
    if (run.length.isOdd) {
      out.write('\n');
    }
    return out.toString();
  });
}

String _stripBlankLineSentinelForDisplay(String markdown) {
  if (markdown.isEmpty || !markdown.contains(_blankLineSentinel)) {
    return markdown;
  }
  // Defensive: never allow the internal blank-line sentinel to reach any
  // user-visible output (rendering/copy/export).
  return markdown.replaceAll(_blankLineSentinel, '');
}

quill_delta.Delta _stripBlankLineSentinel(quill_delta.Delta source) {
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
    if (!value.contains(_blankLineSentinel)) {
      result.insert(value, operation.attributes);
      continue;
    }
    final stripped = value.replaceAll(_blankLineSentinel, '');
    if (stripped.isNotEmpty) {
      result.insert(stripped, operation.attributes);
    }
  }
  return result;
}

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

void assertNoHtmlMedia(String markdown) {
  if (markdown.isEmpty) return;
  if (_forbiddenHtmlMediaPattern.hasMatch(markdown)) {
    throw StateError(
      'Canonical text contract violation: HTML media tags are forbidden. '
      'Use !video(id), !audio(id), !image(id), or !document(id).',
    );
  }
}

void assertNoRawMarkdownMediaRefs(String markdown) {
  if (markdown.isEmpty) return;

  for (final match in _markdownImagePattern.allMatches(markdown)) {
    final raw = match.group(0)?.trim();
    if (raw == null || raw.isEmpty) {
      continue;
    }
    throw StateError(
      'Canonical text contract violation: media refs must use typed '
      'lesson_media ids. Raw image URLs are not allowed.',
    );
  }

  for (final match in _markdownLinkPattern.allMatches(markdown)) {
    final raw = match.group(0)?.trim();
    final source = match.group(2)?.trim();
    if (raw == null || raw.isEmpty || source == null || source.isEmpty) {
      continue;
    }
    final isLegacyMediaLink =
        studioMediaUrlPattern.hasMatch(source) ||
        mediaStreamUrlPattern.hasMatch(source) ||
        apiFilesUrlPattern.hasMatch(source);
    if (!isLegacyMediaLink) {
      continue;
    }
    throw StateError(
      'Canonical text contract violation: media refs must use typed '
      'lesson_media ids. Raw document/media links are not allowed.',
    );
  }
}

String rewriteLessonMarkdownDocumentLinksForEditor({
  required String markdown,
  Map<String, String> lessonMediaDocumentLabelsById = const <String, String>{},
}) {
  if (markdown.isEmpty) return markdown;

  final normalizedLabels = <String, String>{
    for (final entry in lessonMediaDocumentLabelsById.entries)
      if (entry.key.trim().isNotEmpty) entry.key.trim(): entry.value.trim(),
  };

  String buildInternalDocumentLink({
    required String lessonMediaId,
    String? rawLabel,
  }) {
    final label = _documentLinkLabel(
      rawLabel: rawLabel,
      fileName: normalizedLabels[lessonMediaId],
    ).replaceAll('[', '(').replaceAll(']', ')');
    return '[$label](${lessonMediaDocumentLinkUrl(lessonMediaId)})';
  }

  var rewritten = markdown.replaceAllMapped(_lessonDocumentTokenPattern, (
    match,
  ) {
    final lessonMediaId = match.group(1)?.trim();
    if (lessonMediaId == null || lessonMediaId.isEmpty) {
      return match.group(0) ?? '';
    }
    return buildInternalDocumentLink(lessonMediaId: lessonMediaId);
  });

  rewritten = rewritten.replaceAllMapped(_markdownLinkPattern, (match) {
    final raw = match.group(0) ?? '';
    final lessonMediaId = lessonMediaIdFromDocumentLinkUrl(match.group(2));
    if (lessonMediaId == null || lessonMediaId.isEmpty) {
      return raw;
    }
    return buildInternalDocumentLink(
      lessonMediaId: lessonMediaId,
      rawLabel: match.group(1),
    );
  });

  return rewritten;
}

String normalizeDocumentMarkdownLinksToTokens(String markdown) {
  if (markdown.isEmpty) return markdown;

  return markdown.replaceAllMapped(_markdownLinkPattern, (match) {
    final raw = match.group(0) ?? '';
    final rawUrl = match.group(2);
    if (!_isInternalLessonMediaDocumentLinkUrl(rawUrl)) {
      return raw;
    }
    final lessonMediaId = lessonMediaIdFromDocumentLinkUrl(rawUrl);
    if (lessonMediaId == null || lessonMediaId.isEmpty) {
      _throwCanonicalMediaWriteViolation(raw);
    }
    return _lessonMediaToken(kind: 'document', lessonMediaId: lessonMediaId);
  });
}

quill_delta.Delta _replaceHtmlTagWithEmbed(
  quill_delta.Delta source,
  RegExp pattern,
  dynamic Function(RegExpMatch match) embedFactory,
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
        result.insert(embedFactory(match), operation.attributes);
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
      final lessonMediaId = _lessonMediaIdFromMediaAttributes(attrs);
      if (src.isEmpty && (lessonMediaId == null || lessonMediaId.isEmpty)) {
        if (raw.isNotEmpty) {
          result.insert(raw, operation.attributes);
        }
      } else {
        final attributes = operation.attributes;
        final mergedAttrs = attributes == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(attributes);

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

        final alt = attrs['alt'];
        final imageValue = lessonMediaId != null && lessonMediaId.isNotEmpty
            ? imageBlockEmbedValueFromLessonMedia(
                lessonMediaId: lessonMediaId,
                alt: alt,
              )
            : src;

        result.insert(
          quill.BlockEmbed.image(imageValue),
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

quill_delta.Delta _replaceTokenWithEmbed(
  quill_delta.Delta source,
  RegExp pattern,
  dynamic Function(String lessonMediaId) embedFactory,
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

      final lessonMediaId = match.group(1)?.trim();
      if (lessonMediaId == null || lessonMediaId.isEmpty) {
        final raw = match.group(0) ?? '';
        if (raw.isNotEmpty) {
          result.insert(raw, operation.attributes);
        }
      } else {
        result.insert(embedFactory(lessonMediaId), operation.attributes);
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

quill_delta.Delta convertLessonMarkdownToDelta(
  MarkdownToDelta converter,
  String markdown,
) {
  final prepared = _preserveExtraBlankLinesForDelta(markdown);
  final converted = _stripBlankLineSentinel(converter.convert(prepared));
  final withAudio = _replaceHtmlTagWithEmbed(converted, _audioHtmlTagPattern, (
    match,
  ) {
    final raw = match.group(0) ?? '';
    final attrs = _parseHtmlAttributes(raw);
    final src = _normalizeMediaSourceAttribute(attrs);
    final id = _lessonMediaIdFromMediaAttributes(attrs);
    if (id != null && id.isNotEmpty) {
      return AudioBlockEmbed.fromLessonMedia(lessonMediaId: id);
    }
    final extractedSrc = match.group(1)?.trim() ?? '';
    if (extractedSrc.isNotEmpty) {
      return AudioBlockEmbed.fromUrl(extractedSrc);
    }
    if (src.isNotEmpty) {
      return AudioBlockEmbed.fromUrl(src);
    }
    return raw;
  });
  final withVideo = _replaceHtmlTagWithEmbed(withAudio, _videoHtmlTagPattern, (
    match,
  ) {
    final raw = match.group(0) ?? '';
    final attrs = _parseHtmlAttributes(raw);
    final src = _normalizeMediaSourceAttribute(attrs);
    final id = _lessonMediaIdFromMediaAttributes(attrs);
    if (id != null && id.isNotEmpty) {
      return quill.BlockEmbed.video(
        videoBlockEmbedValueFromLessonMedia(lessonMediaId: id),
      );
    }
    final extractedSrc = match.group(1)?.trim() ?? '';
    if (extractedSrc.isNotEmpty) {
      return quill.BlockEmbed.video(extractedSrc);
    }
    if (src.isNotEmpty) {
      return quill.BlockEmbed.video(src);
    }
    return raw;
  });
  final withImages = _replaceHtmlImgTagsWithEmbeds(withVideo);
  final withAudioTokens = _replaceTokenWithEmbed(
    withImages,
    _lessonAudioTokenPattern,
    (lessonMediaId) =>
        AudioBlockEmbed.fromLessonMedia(lessonMediaId: lessonMediaId),
  );
  final withVideoTokens = _replaceTokenWithEmbed(
    withAudioTokens,
    _lessonVideoTokenPattern,
    (lessonMediaId) => quill.BlockEmbed.video(
      videoBlockEmbedValueFromLessonMedia(lessonMediaId: lessonMediaId),
    ),
  );
  final withImageTokens = _replaceTokenWithEmbed(
    withVideoTokens,
    _lessonImageTokenPattern,
    (lessonMediaId) => quill.BlockEmbed.image(
      imageBlockEmbedValueFromLessonMedia(lessonMediaId: lessonMediaId),
    ),
  );
  return withImageTokens;
}

String? _lessonMediaIdFromMediaAttributes(Map<String, String> attrs) {
  final explicit =
      attrs['data-lesson-media-id'] ?? attrs['data-lesson_media_id'];
  if (explicit != null && explicit.trim().isNotEmpty) return explicit.trim();
  return null;
}

final RegExp studioMediaUrlPattern = RegExp(
  r'''(?:https?:\/\/[^\s"'()]+)?\/studio\/media\/''' + _lessonMediaIdFragment,
  caseSensitive: false,
);

final RegExp apiFilesUrlPattern = RegExp(
  r'''(?:https?:\/\/[^\s"'()]+)?\/api\/files\/[^\s"'()]+''',
  caseSensitive: false,
);

final RegExp mediaStreamUrlPattern = RegExp(
  r'''(?:https?:\/\/[^\s"'()]+)?\/media\/stream\/([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)''',
);

final RegExp lessonMediaIdAttributePattern = RegExp(
  r'''data-lesson-media-id\s*=\s*["']''' + _lessonMediaIdFragment + r'''["']''',
  caseSensitive: false,
);

Set<String> extractLessonEmbeddedMediaIds(String markdown) {
  final ids = <String>{};
  for (final match in lessonMediaIdAttributePattern.allMatches(markdown)) {
    final id = match.group(1);
    if (id != null && id.isNotEmpty) {
      ids.add(id);
    }
  }
  for (final match in _lessonImageTokenPattern.allMatches(markdown)) {
    final id = match.group(1);
    if (id != null && id.isNotEmpty) {
      ids.add(id);
    }
  }
  for (final match in _lessonAudioTokenPattern.allMatches(markdown)) {
    final id = match.group(1);
    if (id != null && id.isNotEmpty) {
      ids.add(id);
    }
  }
  for (final match in _lessonVideoTokenPattern.allMatches(markdown)) {
    final id = match.group(1);
    if (id != null && id.isNotEmpty) {
      ids.add(id);
    }
  }
  for (final match in _lessonDocumentTokenPattern.allMatches(markdown)) {
    final id = match.group(1);
    if (id != null && id.isNotEmpty) {
      ids.add(id);
    }
  }
  for (final match in _markdownLinkPattern.allMatches(markdown)) {
    final id = lessonMediaIdFromDocumentLinkUrl(match.group(2));
    if (id != null && id.isNotEmpty) {
      ids.add(id);
    }
  }
  return ids;
}

String rewriteLessonMarkdownApiFilesUrls({
  required String markdown,
  required Map<String, String> apiFilesPathToStudioMediaUrl,
}) {
  if (markdown.isEmpty || apiFilesPathToStudioMediaUrl.isEmpty) return markdown;

  return markdown.replaceAllMapped(apiFilesUrlPattern, (match) {
    final raw = match.group(0) ?? '';
    if (raw.isEmpty) return raw;
    final uri = Uri.tryParse(raw);
    final path = uri?.path ?? raw;
    if (path.isEmpty) return raw;
    final replacement =
        apiFilesPathToStudioMediaUrl[path] ??
        apiFilesPathToStudioMediaUrl[path.toLowerCase()];
    if (replacement == null || replacement.isEmpty) return raw;
    return replacement;
  });
}

String rewriteLegacyLessonMediaUrlsForReadCompatibility({
  required String markdown,
  Iterable<LessonMediaItem> lessonMedia = const <LessonMediaItem>[],
}) {
  return markdown;
}

Future<String> prepareLessonMarkdownForRendering(
  MediaRepository mediaRepository,
  String markdown, {
  Iterable<LessonMediaItem> lessonMedia = const <LessonMediaItem>[],
  Object? pipelineRepository,
}) async {
  markdown = _stripBlankLineSentinelForDisplay(markdown);
  if (markdown.trim().isEmpty) return markdown;
  final documentLabelsById = <String, String>{
    for (final item in lessonMedia)
      if (item.id.trim().isNotEmpty) item.id.trim(): item.fileName,
  };
  return rewriteLessonMarkdownDocumentLinksForEditor(
    markdown: markdown,
    lessonMediaDocumentLabelsById: documentLabelsById,
  );
}

String normalizeLessonMarkdownForStorage(String markdown) {
  if (markdown.isEmpty) return markdown;

  var normalized = normalizeDocumentMarkdownLinksToTokens(markdown);
  normalized = normalized.replaceAll(_blankLineSentinel, '');
  assertNoHtmlMedia(normalized);
  assertNoRawMarkdownMediaRefs(normalized);
  return normalized;
}
