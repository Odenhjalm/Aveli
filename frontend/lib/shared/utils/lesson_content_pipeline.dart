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
/// Active runtime accepts only canonical lesson-media references and rejects
/// raw HTML or URL-based media shapes.

class AudioBlockEmbed extends quill.CustomBlockEmbed {
  static const String embedType = 'audio';

  const AudioBlockEmbed(String data) : super(embedType, data);

  /// Stable embed marker for lesson media audio.
  static AudioBlockEmbed fromLessonMedia({required String lessonMediaId}) =>
      AudioBlockEmbed(lessonMediaId);
}

String videoBlockEmbedValueFromLessonMedia({required String lessonMediaId}) =>
    lessonMediaId;

String imageBlockEmbedValueFromLessonMedia({
  required String lessonMediaId,
  String? alt,
}) => lessonMediaId;

String? _lessonMediaIdFromEmbedValue(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }

  return null;
}

String? lessonMediaIdFromEmbedValue(dynamic value) =>
    _lessonMediaIdFromEmbedValue(value);

String? lessonMediaAltFromEmbedValue(Object? value) => null;

String? normalizeVideoPlaybackUrl(String? rawValue) {
  if (rawValue == null || rawValue.isEmpty) return null;
  final uri = Uri.tryParse(rawValue);
  if (uri == null) return null;
  final scheme = uri.scheme;
  if (scheme != 'http' && scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return rawValue;
}

String _lessonMediaToken({
  required String kind,
  required String lessonMediaId,
}) => '!$kind($lessonMediaId)';

const String _lessonMediaDocumentLinkScheme = 'aveli-document';

String lessonMediaDocumentLinkUrl(String lessonMediaId) =>
    '$_lessonMediaDocumentLinkScheme://$lessonMediaId';

bool _isInternalLessonMediaDocumentLinkUrl(String? rawUrl) {
  if (rawUrl == null || rawUrl.isEmpty) {
    return false;
  }
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) {
    return false;
  }
  return uri.scheme == _lessonMediaDocumentLinkScheme;
}

String? lessonMediaIdFromDocumentLinkUrl(String? rawUrl) {
  if (rawUrl == null || rawUrl.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(rawUrl);
  if (uri != null && uri.scheme == _lessonMediaDocumentLinkScheme) {
    final host = uri.host;
    if (host.isNotEmpty) {
      return host;
    }
  }

  return null;
}

String _documentLinkLabel({String? rawLabel, String? fileName}) {
  final resolved = rawLabel != null && rawLabel.isNotEmpty
      ? rawLabel
      : (fileName != null && fileName.isNotEmpty ? fileName : 'Dokument');
  if (resolved.startsWith('📄 ')) {
    return resolved;
  }
  return '📄 $resolved';
}

Never _throwCanonicalMediaWriteViolation(String raw) {
  throw StateError(
    'Canonical text contract violation: media refs must use typed '
    'lesson_media ids. Could not normalize $raw.',
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
        _throwCanonicalMediaWriteViolation('${embed.value.data}');
      },
      quill.BlockEmbed.imageType: (embed, out) {
        final lessonMediaId = _lessonMediaIdFromEmbedValue(embed.value.data);
        if (lessonMediaId != null && lessonMediaId.isNotEmpty) {
          out.write(
            _lessonMediaToken(kind: 'image', lessonMediaId: lessonMediaId),
          );
          return;
        }
        _throwCanonicalMediaWriteViolation('${embed.value.data}');
      },
      quill.BlockEmbed.videoType: (embed, out) {
        final lessonMediaId = _lessonMediaIdFromEmbedValue(embed.value.data);
        if (lessonMediaId != null && lessonMediaId.isNotEmpty) {
          out.write(
            _lessonMediaToken(kind: 'video', lessonMediaId: lessonMediaId),
          );
          return;
        }
        _throwCanonicalMediaWriteViolation('${embed.value.data}');
      },
    },
  );
}

MarkdownToDelta createLessonMarkdownToDelta(md.Document markdownDocument) {
  return MarkdownToDelta(markdownDocument: markdownDocument);
}

const String _lessonMediaIdFragment = r'([A-Za-z0-9_-]+(?:-[A-Za-z0-9_-]+)*)';

final RegExp _forbiddenHtmlMediaPattern = RegExp(
  r'<\s*(video|audio|img)\b',
  caseSensitive: false,
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
    final raw = match.group(0);
    if (raw == null || raw.isEmpty) {
      continue;
    }
    throw StateError(
      'Canonical text contract violation: media refs must use typed '
      'lesson_media ids. Raw image URLs are not allowed.',
    );
  }

  for (final match in _markdownLinkPattern.allMatches(markdown)) {
    final raw = match.group(0);
    final source = match.group(2);
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
      if (entry.key.isNotEmpty) entry.key: entry.value,
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
    final lessonMediaId = match.group(1);
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

      final lessonMediaId = match.group(1);
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
  final withAudioTokens = _replaceTokenWithEmbed(
    converted,
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

Set<String> extractLessonEmbeddedMediaIds(String markdown) {
  final ids = <String>{};
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
  if (apiFilesPathToStudioMediaUrl.isNotEmpty) {
    // Legacy URL rewrite is intentionally disabled in canonical runtime.
  }
  return markdown;
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
  if (markdown.isEmpty) return markdown;
  final documentLabelsById = <String, String>{
    for (final item in lessonMedia)
      if (item.id.isNotEmpty) item.id: item.fileName,
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
