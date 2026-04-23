# LER-015 READING UX MODES

TYPE: `OWNER`
TASK_TYPE: `FRONTEND_READING_UX`
DEPENDS_ON: `[LER-014]`

## Goal

Improve the rebuilt editor and learner reading experience without changing
`lesson_document_v1`, backend APIs, validation, persistence, or media authority.

## Required Outputs

- editor authoring surface uses a clean white writing shell
- internal model, schema, Markdown, Quill, and debug labels are not rendered to
  user-facing editor or preview UI
- Course Editor persisted preview exposes a local Glass/Paper reading-mode
  toggle
- learner lesson content exposes a local Glass/Paper reading-mode toggle
- Paper mode renders a white reading surface with subtle horizontal guide
  lines and high-contrast text
- Glass mode preserves the existing translucent reading style
- reading-mode choice is local UI state only and does not mutate or serialize
  lesson content

## Forbidden

- modifying `lesson_document_v1`
- changing backend APIs or persistence shape
- reintroducing Markdown, Quill, or legacy rendering authority
- making reading mode part of saved lesson content
- rendering internal schema/debug text to users
- letting visual guide lines affect document structure or canonical content

## Verification

Run focused frontend analyzer and widget tests for editor, persisted preview,
and learner rendering. Re-run deterministic no-leak string audit for visible
internal model labels.

## Execution Record

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

### Audit Findings

- `LessonDocumentEditor` used a semitransparent shell color
  `Colors.white.withValues(alpha: 0.92)` even though the inner continuous
  writing surface was white.
- `LessonDocumentEditor` rendered the internal footer text
  `Dokumentmodell: lesson_document_v1. Markdown/Quill ...` to users.
- Course Editor Preview Mode and learner lesson rendering both called
  `LessonDocumentPreview` directly with no selectable reading mode.
- No backend or document-model change was required; the mismatch was
  presentation-only.

### Materialized Outputs

- Updated `frontend/lib/editor/document/lesson_document_editor.dart` so the
  editor shell and continuous writing surface are pure white.
- Removed the user-visible model/Markdown/Quill footer from the editor.
- Added `LessonDocumentReadingMode`, `LessonDocumentReadingModeToggle`, and a
  Paper reading surface wrapper that uses visual-only horizontal lines behind
  existing preview content.
- Updated Course Editor Preview Mode to keep local
  `_lessonPreviewReadingMode` state and pass it to `LessonDocumentPreview`.
- Updated learner lesson content rendering to keep local reading-mode state,
  preserve Glass mode through the existing `GlassCard`, and render Paper mode
  without making the document renderer a persistence authority.
- Reworded preview helper copy so it refers to saved content instead of the
  internal document model.

### Verification Evidence

- `dart format lib\editor\document\lesson_document_editor.dart lib\features\studio\presentation\course_editor_page.dart lib\features\courses\presentation\lesson_page.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart`
  completed.
- `flutter analyze lib\editor\document\lesson_document_editor.dart lib\features\studio\presentation\course_editor_page.dart lib\features\courses\presentation\lesson_page.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart`
  passed with no issues.
- `flutter test test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart`
  passed: `14 passed`.
- Broad task-scoped frontend regression passed:
  `flutter test test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart test\widgets\lesson_media_pipeline_test.dart test\unit\lesson_document_model_test.dart test\unit\studio_repository_lesson_content_read_test`
  returned `41 passed`.
- Deterministic backend audit gates passed:
  `.\.venv\Scripts\python.exe -m pytest backend\tests\test_ler011_deterministic_audit_gates.py backend\tests\test_ler012_final_aggregate_editor_gate.py backend\tests\test_lesson_document_fixture_corpus.py`
  returned `24 passed` with the existing `python_multipart` warning.
- `.\.venv\Scripts\python.exe -m json.tool actual_truth\DETERMINED_TASKS\lesson_editor_rebuild\task_manifest.json`
  completed.
- User-facing string audit found no rendered editor/preview strings containing
  `Dokumentmodell`, `Markdown/Quill`, `sparauktoritet`, or the internal schema
  label in the rebuilt editor UI path. Remaining `lesson_document_v1` and
  `content_document` matches are schema constants, payload fields, or tracing
  labels, not rendered lesson UI.

### Deterministic Result

`LER-015` keeps `lesson_document_v1` as structural authority while making the
editor writing surface white, removing internal UI leakage, and adding local
Glass/Paper reading-mode presentation for persisted preview and learner lesson
reading.
