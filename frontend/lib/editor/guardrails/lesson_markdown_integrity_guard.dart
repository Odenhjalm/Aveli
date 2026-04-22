import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;

import 'package:aveli/editor/adapter/editor_to_markdown.dart'
    as editor_to_markdown;
import 'package:aveli/editor/adapter/markdown_to_editor.dart'
    as markdown_to_editor;

enum LessonMarkdownIntegrityFailureReason {
  markdownRoundTripMismatch,
  semanticRoundTripMismatch,
  markdownAndSemanticRoundTripMismatch,
}

class LessonMarkdownIntegrityGuardResult {
  const LessonMarkdownIntegrityGuardResult._({
    required this.ok,
    required this.failureReason,
    required this.originalMarkdown,
    required this.canonicalMarkdown,
  });

  const LessonMarkdownIntegrityGuardResult.ok({
    required String originalMarkdown,
    required String canonicalMarkdown,
  }) : this._(
         ok: true,
         failureReason: null,
         originalMarkdown: originalMarkdown,
         canonicalMarkdown: canonicalMarkdown,
       );

  const LessonMarkdownIntegrityGuardResult.failure({
    required LessonMarkdownIntegrityFailureReason failureReason,
    required String originalMarkdown,
    required String canonicalMarkdown,
  }) : this._(
         ok: false,
         failureReason: failureReason,
         originalMarkdown: originalMarkdown,
         canonicalMarkdown: canonicalMarkdown,
       );

  final bool ok;
  final LessonMarkdownIntegrityFailureReason? failureReason;
  final String originalMarkdown;
  final String canonicalMarkdown;
}

LessonMarkdownIntegrityGuardResult validateLessonMarkdownIntegrity({
  required quill_delta.Delta delta,
}) {
  final markdown1 = editor_to_markdown.editorDeltaToCanonicalMarkdown(
    delta: delta,
  );
  final delta2 = markdown_to_editor
      .markdownToEditorDocument(markdown: markdown1)
      .toDelta();
  final markdown3 = editor_to_markdown.editorDeltaToCanonicalMarkdown(
    delta: delta2,
  );

  final markdownStable = markdown1 == markdown3;
  final semanticStable =
      _deltaSemanticSignature(delta) == _deltaSemanticSignature(delta2);

  if (markdownStable && semanticStable) {
    return LessonMarkdownIntegrityGuardResult.ok(
      originalMarkdown: markdown1,
      canonicalMarkdown: markdown3,
    );
  }

  return LessonMarkdownIntegrityGuardResult.failure(
    failureReason: _resolveFailureReason(
      markdownStable: markdownStable,
      semanticStable: semanticStable,
    ),
    originalMarkdown: markdown1,
    canonicalMarkdown: markdown3,
  );
}

String _deltaSemanticSignature(quill_delta.Delta delta) {
  final sanitized = editor_to_markdown.sanitizeEditorDeltaForCanonicalMarkdown(
    delta,
  );
  if (sanitized.toList().isEmpty) {
    return '[]';
  }
  final document = quill.Document.fromDelta(sanitized);
  return jsonEncode(document.root.toDelta().toJson());
}

LessonMarkdownIntegrityFailureReason _resolveFailureReason({
  required bool markdownStable,
  required bool semanticStable,
}) {
  if (!markdownStable && !semanticStable) {
    return LessonMarkdownIntegrityFailureReason
        .markdownAndSemanticRoundTripMismatch;
  }
  if (!markdownStable) {
    return LessonMarkdownIntegrityFailureReason.markdownRoundTripMismatch;
  }
  return LessonMarkdownIntegrityFailureReason.semanticRoundTripMismatch;
}
