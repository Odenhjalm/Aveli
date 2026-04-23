# LER-005 EDITOR UI REPLACEMENT

TYPE: `OWNER`
TASK_TYPE: `FRONTEND_EDITOR_REPLACEMENT`
DEPENDS_ON: `[LER-004]`

## Goal

Replace the Course Editor authoring surface with a document-model editor UI.

## Required Outputs

- toolbar commands mutate `lesson_document_v1`
- save serializes `content_document`
- save no longer calls Markdown serialization or Markdown integrity guard
- UI supports bold, italic, underline, clear formatting, headings, bullet lists,
  and ordered lists
- dirty state and ETag handling remain correct

## Forbidden

- calling `serializeEditorDeltaToCanonicalMarkdown` in the new save path
- calling `validateLessonMarkdownIntegrity` in the new save path
- preserving Quill as canonical editor authority

## Verification

Widget tests prove editing and saving all text/block features through
`content_document`.

## Stop Conditions

Stop if the chosen editor UI cannot preserve explicit document block structure.

## Execution Record

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

### Retrieval Inputs

- `actual_truth/DETERMINED_TASKS/lesson_editor_rebuild/LER-005_editor_ui_replacement.md`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/features/studio/data/studio_repository.dart`
- `frontend/lib/features/studio/data/studio_models.dart`
- `frontend/lib/editor/document/lesson_document.dart`
- Existing frontend tests referencing legacy `content_markdown` and Quill

### Materialized Changes

- Added `frontend/lib/editor/document/lesson_document_editor.dart` as the
  Course Editor document-model authoring widget.
- Replaced the Course Editor authoring surface with `LessonDocumentEditor`.
- Replaced active Course Editor save authority with `_lessonDocument` and
  `content_document`.
- Removed `serializeEditorDeltaToCanonicalMarkdown` and
  `validateLessonMarkdownIntegrity` from the active Course Editor save path.
- Updated studio content read/write models so `StudioLessonContentRead` and
  `StudioLessonContentWriteResult` carry `LessonDocument`.
- Updated `StudioRepository.updateLessonContent` to PATCH
  `content_document` under the existing `If-Match` transport token.
- Preserved ETag dirty-state flow: content writes still require a loaded ETag,
  updated responses replace the stored ETag, and 412 / 428 conflicts still
  force reload.
- Added widget coverage proving bold, italic, underline, clear formatting,
  heading, bullet list, ordered list, and direct text editing mutate
  `lesson_document_v1`.
- Added repository coverage proving read/write transport uses
  `content_document`.

### Post-Task Audit

- Active Course Editor save path no longer contains `content_markdown`.
- Active Course Editor save path no longer calls
  `serializeEditorDeltaToCanonicalMarkdown`.
- Active Course Editor save path no longer calls
  `validateLessonMarkdownIntegrity`.
- Quill scaffolding remains only as legacy non-authoritative session/test-bridge
  residue pending `LER-009`; it is not used by the visible authoring surface or
  save payload.
- Media and CTA insertion now create document blocks in the Course Editor, but
  deeper media/CTA renderer alignment and fixture coverage remain under
  `LER-006` and `LER-010`.
- Persisted preview now reads `content_document` and renders a document preview
  component, but full shared learner/preview renderer alignment remains under
  `LER-007` and `LER-008`.

### Verification Evidence

- `flutter analyze lib\editor\document\lesson_document.dart lib\editor\document\lesson_document_editor.dart lib\features\studio\data\studio_models.dart lib\features\studio\data\studio_repository.dart lib\features\studio\presentation\course_editor_page.dart test\unit\studio_repository_lesson_content_read_test.dart test\widgets\lesson_document_editor_test.dart`
- `flutter test test\unit\studio_repository_lesson_content_read_test.dart test\widgets\lesson_document_editor_test.dart`
- Forbidden-path grep over `course_editor_page.dart` for
  `content_markdown`, `serializeEditorDeltaToCanonicalMarkdown`,
  `validateLessonMarkdownIntegrity`, `QuillSimpleToolbar`,
  `QuillEditor.basic`, `_lastSavedLessonMarkdown`, and
  `_lessonPreviewMarkdown` returned no matches.

## Successor State

`LER-006` is now eligible.
