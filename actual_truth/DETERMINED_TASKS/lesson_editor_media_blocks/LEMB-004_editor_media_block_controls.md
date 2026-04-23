# LEMB-004 EDITOR MEDIA BLOCK CONTROLS

TYPE: `OWNER`
TASK_TYPE: `FRONTEND_EDITOR_MEDIA_BLOCK_CONTROLS`
DEPENDS_ON: `[LEMB-002, LEMB-003]`

## Goal

Add deterministic authoring controls for moving non-text media blocks inside
the continuous editor document surface.

## Required Outputs

- media blocks remain non-text blocks inside the single continuous writing
  surface
- selected/focused media block exposes move up/down actions
- move actions call document-model operations rather than ad hoc list mutation
- controls are disabled at document boundaries
- movement updates editor state and serialized document order

## Target Files

- `frontend/lib/editor/document/lesson_document_editor.dart`
- `frontend/test/widgets/lesson_document_editor_test.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`

## Retrieval Queries

- `LessonDocumentEditor LessonMediaBlock focus selected block controls`
- `moveBlockUp moveBlockDown LessonDocumentEditor test`
- `continuous writing surface media block controls`

## Forbidden

- visible per-block container regression
- drag/reorder implementation that bypasses `lesson_document_v1`
- movement that changes media identity, type, text marks, or CTA nodes
- relying on placement reorder APIs for editor document block movement

## Verification Requirement

Widget tests must prove:

- moving a media block up/down changes document order deterministically
- boundary move controls are disabled or no-op deterministically
- editor and preview render the moved media in the same relative position
- no internal id or raw media type appears in the controls

## Execution Record

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

### Pre-Change Audit

- Media blocks already rendered as non-text blocks inside the continuous
  writing surface.
- No move up/down controls existed for editor media blocks.
- Document-model move operations existed from `LEMB-002`.
- Existing tests did not prove editor media movement, boundary-disabled
  controls, or preview order parity after movement.

### Materialized Outputs

- Added editor-level `_moveBlock`, `_moveBlockUp`, and `_moveBlockDown`
  handlers.
- Added generic media move up/down controls to `LessonMediaBlock` rendering.
- Disabled move-up at document start and move-down at document end.
- Wired movement through `LessonDocument.moveBlock`, not placement reorder or
  ad hoc list mutation.
- Added widget tests for moving media up/down, boundary-disabled controls,
  payload identity preservation, generic no-id/no-type control labels, and
  preview order parity.

### Verification Evidence

- `dart format lib\editor\document\lesson_document_editor.dart test\widgets\lesson_document_editor_test.dart`
  completed for 2 files.
- `flutter analyze lib\editor\document\lesson_document_editor.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_media_pipeline_test.dart`
  passed with `No issues found!`.
- `flutter test test\widgets\lesson_document_editor_test.dart test\widgets\lesson_media_pipeline_test.dart`
  passed: `21 passed`.

### Contract Preservation

- `lesson_document_v1` was not changed.
- Backend APIs were not changed.
- Document AST movement does not use media placement reorder APIs.
- Markdown, Quill, and legacy media-token pathways were not introduced.
- Existing media body metadata leakage remains assigned to `LEMB-005`.

### Next Deterministic Step

`LEMB-005 RENDERER UI LEAK CLEANUP`
