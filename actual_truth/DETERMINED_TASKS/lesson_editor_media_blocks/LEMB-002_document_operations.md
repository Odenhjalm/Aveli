# LEMB-002 DOCUMENT OPERATION PRIMITIVES

TYPE: `OWNER`
TASK_TYPE: `FRONTEND_DOCUMENT_OPERATIONS`
DEPENDS_ON: `[LEMB-001]`

## Goal

Add deterministic document-model operations required for media positioning and
movement before editor UI controls depend on them.

## Required Outputs

- document-level operation for inserting media at an explicit block index or
  resolved selection position
- deterministic block movement operation for moving a block up or down
- validation that media movement preserves the exact `LessonMediaBlock`
  identity and media type
- tests proving ordered block output is stable after insert and move

## Target Files

- `frontend/lib/editor/document/lesson_document.dart`
- `frontend/test/unit/lesson_document_model_test.dart`

## Retrieval Queries

- `LessonDocument insertBlock insertMedia blocks unmodifiable move operation`
- `lesson_document_model_test insert media ordered blocks`
- `LessonMediaBlock validation mediaTypesByLessonMediaId`

## Forbidden

- changing backend APIs
- changing persisted schema version
- introducing Markdown, Quill, or legacy token conversion
- allowing move operations to mutate text marks or block payload content
- allowing out-of-range moves to corrupt document order

## Verification Requirement

Focused unit tests must prove:

- media can be inserted before, between, and after text blocks
- moving a media block up/down changes only block order
- boundary moves are deterministic and safe
- serialized JSON remains canonical `lesson_document_v1`

## Execution Record

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

### Pre-Change Audit

- `LessonDocument.insertMedia(index, mediaType, lessonMediaId)` already existed
  and already serialized media as `media_type` / `lesson_media_id`.
- The document model did not expose deterministic block movement operations.
- Existing unit tests did not explicitly prove media insertion before, between,
  and after text blocks or media movement preserving payload identity.

### Materialized Outputs

- Added `LessonDocument.moveBlock(fromIndex, toIndex)`.
- Added `LessonDocument.moveBlockUp(index)`.
- Added `LessonDocument.moveBlockDown(index)`.
- Added unit tests for media insertion before, between, and after text blocks.
- Added unit tests for media block move up/down and explicit target movement.
- Added unit tests for boundary no-op and out-of-range movement behavior.

### Verification Evidence

- `dart format lib\editor\document\lesson_document.dart test\unit\lesson_document_model_test.dart`
  completed for 2 files.
- `flutter analyze lib\editor\document\lesson_document.dart test\unit\lesson_document_model_test.dart`
  passed with `No issues found!`.
- `flutter test test\unit\lesson_document_model_test.dart` passed:
  `14 passed`.

### Contract Preservation

- `lesson_document_v1` schema version was not changed.
- Backend APIs were not changed.
- `media_asset_id` was not introduced into the document model.
- Markdown, Quill, and legacy media-token pathways were not introduced.

### Next Deterministic Step

`LEMB-003 EDITOR POSITIONED MEDIA INSERTION`
