import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_quill/markdown_quill.dart';

import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/shared/utils/lesson_media_playback_resolver.dart';

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

  /// Stable embed marker for lesson media audio.
  ///
  /// The optional `src` is only used for immediate playback while rendering
  /// (editor/student view). It is never persisted to `content_markdown`.
  static AudioBlockEmbed fromLessonMedia({
    required String lessonMediaId,
    String? src,
  }) => AudioBlockEmbed(
    jsonEncode(<String, dynamic>{
      'lesson_media_id': lessonMediaId,
      'kind': 'audio',
      if (src != null && src.trim().isNotEmpty) 'src': src.trim(),
    }),
  );
}

const HtmlEscape _htmlAttributeEscape = HtmlEscape(HtmlEscapeMode.attribute);

@visibleForTesting
String? lessonMediaUrlFromEmbedValue(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    final trimmed = value.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = json.decode(trimmed);
        if (decoded is Map) {
          for (final key in const ['source', 'src', 'url', 'download_url']) {
            final dynamic nested = decoded[key];
            if (nested is String && nested.trim().isNotEmpty) {
              return nested.trim();
            }
          }
          final lessonMediaId = decoded['lesson_media_id'];
          if (lessonMediaId is String && lessonMediaId.trim().isNotEmpty) {
            return '/studio/media/${lessonMediaId.trim()}';
          }
        }
      } catch (_) {
        // Not JSON – fall through.
      }
    }
    return trimmed;
  }
  if (value is Map) {
    for (final key in const ['source', 'src', 'url', 'download_url']) {
      final dynamic nested = value[key];
      if (nested is String && nested.trim().isNotEmpty) {
        return nested.trim();
      }
    }
    final lessonMediaId = value['lesson_media_id'];
    if (lessonMediaId is String && lessonMediaId.trim().isNotEmpty) {
      return '/studio/media/${lessonMediaId.trim()}';
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

    final studioMatch = studioMediaUrlPattern.firstMatch(trimmed);
    final id = studioMatch?.group(1);
    if (id != null && id.isNotEmpty) return id;

    final streamMatch = mediaStreamUrlPattern.firstMatch(trimmed);
    final token = streamMatch?.group(1);
    if (token != null && token.isNotEmpty) {
      final extracted = _extractMediaIdFromToken(token);
      if (extracted != null && extracted.isNotEmpty) return extracted;
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
        final lessonMediaId = _lessonMediaIdFromEmbedValue(embed.value.data);
        if (lessonMediaId != null && lessonMediaId.isNotEmpty) {
          final escapedId = _htmlAttributeEscape.convert(lessonMediaId);
          out.write('<audio controls');
          out.write(' data-lesson-media-id="$escapedId"');
          out.write(' data-kind="audio"');
          out.write(' src="/studio/media/$escapedId"></audio>');
          return;
        }

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
      'audio': (attrs) {
        final src = _normalizeMediaSourceAttribute(attrs);
        final id = _lessonMediaIdFromAudioAttributes(attrs, src);
        if (id != null && id.isNotEmpty) {
          return AudioBlockEmbed.fromLessonMedia(lessonMediaId: id, src: src);
        }
        return AudioBlockEmbed.fromUrl(src);
      },
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
  if (markdown.isEmpty || !markdown.contains(_blankLineSentinel))
    return markdown;
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
  final prepared = _preserveExtraBlankLinesForDelta(markdown);
  final converted = _stripBlankLineSentinel(converter.convert(prepared));
  final withAudio = _replaceHtmlTagWithEmbed(converted, _audioHtmlTagPattern, (
    match,
  ) {
    final raw = match.group(0) ?? '';
    final attrs = _parseHtmlAttributes(raw);
    final src = _normalizeMediaSourceAttribute(attrs);
    final id = _lessonMediaIdFromAudioAttributes(attrs, src);
    if (id != null && id.isNotEmpty) {
      return AudioBlockEmbed.fromLessonMedia(lessonMediaId: id, src: src);
    }
    return AudioBlockEmbed.fromUrl(match.group(1)!.trim());
  });
  final withVideo = _replaceHtmlTagWithEmbed(
    withAudio,
    _videoHtmlTagPattern,
    (match) => quill.BlockEmbed.video(match.group(1)!.trim()),
  );
  final withImages = _replaceHtmlImgTagsWithEmbeds(withVideo);
  return withImages;
}

String? _lessonMediaIdFromAudioAttributes(
  Map<String, String> attrs,
  String src,
) {
  final explicit =
      attrs['data-lesson-media-id'] ?? attrs['data-lesson_media_id'];
  if (explicit != null && explicit.trim().isNotEmpty) return explicit.trim();
  if (src.isEmpty) return null;

  final studioMatch = studioMediaUrlPattern.firstMatch(src);
  final studioId = studioMatch?.group(1);
  if (studioId != null && studioId.isNotEmpty) return studioId;

  final streamMatch = mediaStreamUrlPattern.firstMatch(src);
  final token = streamMatch?.group(1);
  if (token == null || token.isEmpty) return null;
  return _extractMediaIdFromToken(token);
}

final RegExp studioMediaUrlPattern = RegExp(
  r'''(?:https?:\/\/[^\s"'()]+)?\/studio\/media\/([0-9a-fA-F-]{36})''',
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
  r'''data-lesson-media-id\s*=\s*["']([0-9a-fA-F-]{36})["']''',
  caseSensitive: false,
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
  for (final match in lessonMediaIdAttributePattern.allMatches(markdown)) {
    final id = match.group(1);
    if (id != null && id.isNotEmpty) {
      ids.add(id);
    }
  }
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

Future<String> prepareLessonMarkdownForRendering(
  MediaRepository mediaRepository,
  String markdown, {
  Iterable<LessonMediaItem> lessonMedia = const <LessonMediaItem>[],
  MediaPipelineRepository? pipelineRepository,
}) async {
  markdown = _stripBlankLineSentinelForDisplay(markdown);
  if (markdown.trim().isEmpty) return markdown;

  final ids = extractLessonEmbeddedMediaIds(markdown);
  if (ids.isEmpty) return markdown;

  final byId = <String, LessonMediaItem>{
    for (final item in lessonMedia) item.id: item,
  };

  final resolvedUrls = <String, String>{};
  await Future.wait(
    ids.map((id) async {
      try {
        final item = byId[id];
        if (item != null && pipelineRepository != null) {
          final url = await resolveLessonMediaPlaybackUrl(
            item: item,
            mediaRepository: mediaRepository,
            pipelineRepository: pipelineRepository,
          );
          if (url != null && url.trim().isNotEmpty) {
            resolvedUrls[id] = url.trim();
          }
          return;
        }

        final signed = await mediaRepository.signMedia(id);
        try {
          resolvedUrls[id] = mediaRepository.resolveUrl(signed.signedUrl);
        } catch (_) {
          resolvedUrls[id] = signed.signedUrl;
        }
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint(
            '[lesson_content_pipeline] Failed to resolve embedded media id=$id error=$error',
          );
          debugPrint(stackTrace.toString());
        }
      }
    }),
  );
  if (resolvedUrls.isEmpty) return markdown;

  var resolved = markdown;
  resolved = resolved.replaceAllMapped(studioMediaUrlPattern, (match) {
    final id = match.group(1);
    if (id == null || id.isEmpty) return match.group(0) ?? '';
    return resolvedUrls[id] ?? (match.group(0) ?? '');
  });
  resolved = resolved.replaceAllMapped(mediaStreamUrlPattern, (match) {
    final token = match.group(1);
    if (token == null || token.isEmpty) return match.group(0) ?? '';
    final id = _extractMediaIdFromToken(token);
    if (id == null || id.isEmpty) return match.group(0) ?? '';
    return resolvedUrls[id] ?? (match.group(0) ?? '');
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
