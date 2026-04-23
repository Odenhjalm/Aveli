# LESSON EDITOR REBUILD AUDIT FOR CONTRACT

## STATUS

AUDIT FOUNDATION

## 1. AUDIT VERDICT

The current editor does not provide a stable enough foundation for the required
future editor.

The failures reported during authoring are consistent with the codebase:

- authored line and paragraph boundaries are converted through Markdown and
  normalized by regex
- italic is represented through Markdown delimiter conversion and repair
  heuristics
- save can fail closed when Markdown and semantic round trips disagree
- backend validation depends on a Flutter markdown round-trip harness

The correct contract direction is not another local Markdown patch. The correct
contract direction is a versioned document model where formatting, blocks,
media, CTA, preview, and concurrency are explicit.

## 2. CURRENT EDITOR STACK EVIDENCE

Current frontend dependencies bind the editor stack to Quill and Markdown
conversion:

- `frontend/pubspec.yaml:64` uses `flutter_quill`
- `frontend/pubspec.yaml:65` uses `flutter_quill_extensions`
- `frontend/pubspec.yaml:66` uses `markdown`
- `frontend/pubspec.yaml:67` uses `markdown_quill`
- `frontend/pubspec.yaml:71` uses `markdown_widget`

This is not just a rendering choice. It is the active save architecture.

## 3. CURRENT SAVE PATH EVIDENCE

The current studio save path serializes editor state into Markdown before
persistence:

- `frontend/lib/features/studio/presentation/course_editor_page.dart:3443`
  defines `_saveLessonContent`
- `frontend/lib/features/studio/presentation/course_editor_page.dart:3473`
  calls `serializeEditorDeltaToCanonicalMarkdown`
- `frontend/lib/features/studio/presentation/course_editor_page.dart:3483`
  calls `validateLessonMarkdownIntegrity`
- `frontend/lib/features/studio/presentation/course_editor_page.dart:3511`
  can block save with the lesson Markdown integrity error
- `frontend/lib/features/studio/presentation/course_editor_page.dart:3532`
  can block save with the same integrity error
- `frontend/lib/features/studio/presentation/course_editor_page.dart:3566`
  writes through `updateLessonContent`
- `frontend/lib/features/studio/presentation/course_editor_page.dart:3569`
  sends `ifMatch: contentEtag`

ETag concurrency exists and should be preserved. The Markdown conversion and
guard path should not be preserved as the new editor authority.

## 4. CURRENT TOOLBAR AND FEATURE EVIDENCE

The current editor exposes several required authoring affordances:

- `frontend/lib/features/studio/presentation/course_editor_page.dart:3772`
  configures `QuillSimpleToolbarConfig`
- `frontend/lib/features/studio/presentation/course_editor_page.dart:3778`
  enables italic
- `frontend/lib/features/studio/presentation/course_editor_page.dart:3779`
  enables underline
- `frontend/lib/features/studio/presentation/course_editor_page.dart:3645`
  implements magic-link insertion
- `frontend/lib/features/studio/presentation/course_editor_page.dart:5437`
  implements media insertion

The rebuild must preserve the product capabilities, not the Quill
implementation.

## 5. CURRENT MARKDOWN ADAPTER EVIDENCE

Markdown serialization has multiple repair and normalization layers:

- `frontend/lib/editor/adapter/editor_to_markdown.dart:48` repairs terminal
  space-separated italic Markdown
- `frontend/lib/editor/adapter/editor_to_markdown.dart:83` creates
  `DeltaToMarkdown`
- `frontend/lib/editor/adapter/editor_to_markdown.dart:267` normalizes Delta
  for guard behavior
- `frontend/lib/editor/adapter/editor_to_markdown.dart:270` converts Delta to
  Markdown
- `frontend/lib/editor/adapter/editor_to_markdown.dart:275` runs italic repair
- `frontend/lib/editor/adapter/editor_to_markdown.dart:276` canonicalizes
  supported Markdown

Markdown hydration also normalizes emphasis and paragraph gaps:

- `frontend/lib/editor/adapter/markdown_to_editor.dart:85` defines
  `_excessParagraphGapPattern = RegExp(r'\n{4,}')`
- `frontend/lib/editor/adapter/markdown_to_editor.dart:118` defines
  `canonicalizeSupportedMarkdown`
- `frontend/lib/editor/adapter/markdown_to_editor.dart:223` collapses excess
  paragraph gaps to `\n\n`
- `frontend/lib/editor/adapter/markdown_to_editor.dart:385` hydrates Markdown
  for the editor

Validation comparison also collapses newline runs:

- `frontend/lib/editor/adapter/lesson_markdown_validation.dart:55` defines
  validation comparison normalization
- `frontend/lib/editor/adapter/lesson_markdown_validation.dart:65` replaces
  `\n{3,}` with `\n\n`

These transformations are incompatible with an editor contract that treats
paragraph and block boundaries as explicit authored structure.

## 6. CURRENT GUARDRAIL EVIDENCE

The integrity guard is a fail-closed Markdown round-trip gate:

- `frontend/lib/editor/guardrails/lesson_markdown_integrity_guard.dart:49`
  defines `validateLessonMarkdownIntegrity`
- `frontend/lib/editor/guardrails/lesson_markdown_integrity_guard.dart:98`
  returns combined Markdown and semantic round-trip mismatch
- `frontend/lib/editor/guardrails/lesson_markdown_integrity_guard.dart:101`
  returns Markdown round-trip mismatch
- `frontend/lib/editor/guardrails/lesson_markdown_integrity_guard.dart:103`
  returns semantic round-trip mismatch

Fail-closed validation is correct as a principle. The failure is that Markdown
round-trip equivalence is the wrong validation authority for the future editor.

## 7. CURRENT LIVE INPUT PATCH EVIDENCE

The editor has a custom controller that patches Quill operation behavior:

- `frontend/lib/editor/session/editor_operation_controller.dart:22` overrides
  `replaceText`
- `frontend/lib/editor/session/editor_operation_controller.dart:49` strips
  inline attributes from live newline insertion
- `frontend/lib/editor/session/editor_operation_controller.dart:103`
  overrides `replaceTextWithEmbeds`

This confirms that live editing semantics are being repaired around Quill
rather than owned by a purpose-built Aveli document model.

## 8. CURRENT BACKEND VALIDATION EVIDENCE

The backend validates Markdown by running a Flutter round-trip harness:

- `backend/app/utils/lesson_markdown_validator.py:14` points to
  `lesson_markdown_roundtrip_harness_test.dart`
- `backend/app/utils/lesson_markdown_validator.py:59` defines
  `validate_lesson_markdown`
- `backend/app/utils/lesson_markdown_validator.py:75` requires a `flutter`
  executable
- `backend/app/utils/lesson_markdown_validator.py:127` runs the Flutter
  harness
- `backend/app/services/courses_service.py:2199` calls
  `lesson_markdown_validator.validate_lesson_markdown`
- `backend/app/services/courses_service.py:2235` rejects invalid lesson
  Markdown

Backend validation must become backend-native document validation.

## 9. CURRENT NEWLINE TEST EVIDENCE

There is already evidence of frontend/backend semantic tension:

- `frontend/test/unit/lesson_newline_persistence_test.dart:20` uses
  `Hello world\n\nThis is a lesson\n`
- `frontend/test/unit/lesson_newline_persistence_test.dart:21` expects
  `Hello world\n\nThis is a lesson`
- `backend/tests/test_lesson_newline_persistence.py:139` writes
  `Hello world\n\n\n\nThis is a lesson\n\n`
- `backend/tests/test_lesson_newline_persistence.py:163` asserts storage
  preserves the edited Markdown exactly

The future editor should not encode paragraph semantics as newline-count
survival. It should encode paragraphs as paragraph nodes.

## 10. CONTRACT IMPLICATION

The contract must decide the editor at the model layer:

- persisted content is `lesson_document_v1`
- Markdown is legacy compatibility, import, or export only
- block boundaries are explicit nodes
- inline formatting is explicit marks
- media and CTA are explicit nodes
- backend validation is schema and reference validation
- preview renders persisted document truth
- ETag concurrency remains mandatory

Any task that tries to keep the current Markdown round-trip save path as the
new editor authority is contrary to this audit.
