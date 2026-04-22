import 'package:flutter_quill/quill_delta.dart' as quill_delta;

import 'package:aveli/editor/adapter/lesson_markdown_validation.dart'
    as lesson_markdown_validation;
import 'package:aveli/editor/adapter/editor_to_markdown.dart'
    as editor_to_markdown;

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
  Map<String, String> lessonMediaDocumentLabelsById = const <String, String>{},
}) {
  final markdown1 = editor_to_markdown.editorDeltaToCanonicalMarkdown(
    delta: delta,
  );
  final roundTrip = lesson_markdown_validation
      .roundTripLessonMarkdownForValidation(
        markdown: markdown1,
        lessonMediaDocumentLabelsById: lessonMediaDocumentLabelsById,
      );

  final markdownStable =
      lesson_markdown_validation.normalizeLessonMarkdownForValidationComparison(
        markdown1,
      ) ==
      roundTrip.comparisonMarkdown;
  final semanticStable =
      lesson_markdown_validation.deltaSemanticSignatureForValidation(delta) ==
      lesson_markdown_validation.deltaSemanticSignatureForValidation(
        roundTrip.delta,
      );

  final canonicalMarkdown = roundTrip.canonicalMarkdown;

  if (markdownStable && semanticStable) {
    return LessonMarkdownIntegrityGuardResult.ok(
      originalMarkdown: markdown1,
      canonicalMarkdown: canonicalMarkdown,
    );
  }

  return LessonMarkdownIntegrityGuardResult.failure(
    failureReason: _resolveFailureReason(
      markdownStable: markdownStable,
      semanticStable: semanticStable,
    ),
    originalMarkdown: markdown1,
    canonicalMarkdown: canonicalMarkdown,
  );
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
