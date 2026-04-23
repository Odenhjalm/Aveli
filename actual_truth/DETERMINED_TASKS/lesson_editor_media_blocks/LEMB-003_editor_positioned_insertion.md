# LEMB-003 EDITOR POSITIONED MEDIA INSERTION

TYPE: `OWNER`
TASK_TYPE: `FRONTEND_EDITOR_POSITIONED_INSERTION`
DEPENDS_ON: `[LEMB-002]`

## Goal

Replace Course Editor append-only media insertion with insertion at the active
document cursor/selection position.

## Required Outputs

- editor state exposes or resolves the current document insertion index
- `_insertMediaBlockIntoDocument` stops using
  `_lessonDocument.blocks.length` as the unconditional target
- image, audio, video, and document insertion all route through the same
  positioned insertion path
- collapsed cursor insertion and selected-range insertion are deterministic
- no media is appended outside document flow

## Target Files

- `frontend/lib/editor/document/lesson_document_editor.dart`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/test/widgets/lesson_document_editor_test.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`

## Retrieval Queries

- `_insertMediaBlockIntoDocument insertMedia blocks.length`
- `LessonDocumentEditor selected block selection insertion index`
- `_insertImageIntoLesson _insertVideoIntoLesson _insertAudioIntoLesson _insertDocumentIntoLesson`
- `lesson media pipeline inline document tokens without trailing fallback`

## Forbidden

- appending media to document tail when the active position is elsewhere
- creating a separate media section outside `document.blocks`
- changing `lesson_document_v1`
- changing backend APIs
- using Markdown or Quill as insertion authority

## Verification Requirement

Widget tests must prove:

- media insertion after a paragraph appears after that paragraph
- media insertion between two text regions appears between them
- insertion does not alter surrounding text formatting or block identity
- persisted preview receives the same block order as the editor document

## Execution Record

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

### Pre-Change Audit

- `LessonDocumentEditor` had private `_selectedTarget` state but did not expose
  a document insertion index to Course Editor.
- `_insertMediaBlockIntoDocument` inserted at `_lessonDocument.blocks.length`,
  making image, audio, video, and document insertions append-only.
- Renderer code already iterated `document.blocks`; the issue was authored
  block position, not renderer append behavior.

### Materialized Outputs

- Added optional `LessonDocumentEditor.onInsertionIndexChanged`.
- Added deterministic insertion-index resolution from active text target.
- Added `_lessonDocumentInsertionIndex` state to Course Editor.
- Clamped insertion index on document changes and reset it on lesson hydration
  boundaries.
- Updated `_insertMediaBlockIntoDocument` to call
  `_resolvedLessonDocumentInsertionIndex()` instead of unconditional
  `_lessonDocument.blocks.length`.
- Added widget coverage proving selected text position inserts media between
  text blocks and after the later active paragraph.
- Added widget coverage proving preview receives the same document order.

### Verification Evidence

- `dart format lib\editor\document\lesson_document_editor.dart lib\features\studio\presentation\course_editor_page.dart test\widgets\lesson_document_editor_test.dart`
  completed for 3 files.
- `flutter analyze lib\editor\document\lesson_document_editor.dart lib\features\studio\presentation\course_editor_page.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_media_pipeline_test.dart`
  passed with `No issues found!`.
- `flutter test test\widgets\lesson_document_editor_test.dart test\widgets\lesson_media_pipeline_test.dart`
  passed: `20 passed`.

### Contract Preservation

- `lesson_document_v1` was not changed.
- Backend APIs were not changed.
- Media blocks still use `media_type` and `lesson_media_id`.
- Markdown, Quill, and legacy media-token pathways were not introduced.

### Next Deterministic Step

`LEMB-004 EDITOR MEDIA BLOCK CONTROLS`
