# LEMB-005 RENDERER UI LEAK CLEANUP

TYPE: `OWNER`
TASK_TYPE: `FRONTEND_RENDERER_UI_LEAK_CLEANUP`
DEPENDS_ON: `[LEMB-001]`

## Goal

Remove internal media identifiers and raw media type/debug labels from
user-facing editor, preview, and learner UI while preserving internal
resolution metadata.

## Required Outputs

- editor media blocks show safe user-facing copy only
- default preview media fallback shows safe user-facing copy only
- Studio preview labels do not fall back to `media_asset_id`
- learner labels do not fall back to `media_asset_id`
- missing media copy does not expose `lesson_media_id`, `media_asset_id`, raw
  `media_type`, schema names, or debug labels

## Target Files

- `frontend/lib/editor/document/lesson_document_editor.dart`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/features/courses/presentation/lesson_page.dart`
- `frontend/test/widgets/lesson_document_editor_test.dart`
- `frontend/test/widgets/lesson_preview_rendering_test.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`

## Retrieval Queries

- `Media: block.mediaType block.lessonMediaId LessonDocumentEditor`
- `LessonDocumentPreviewMedia label mediaAssetId`
- `_lessonMediaLabel mediaAssetId lesson_page`
- `debug labels lesson_document_v1 Markdown Quill rendered UI`

## Forbidden

- rendering `lesson_media_id`
- rendering `media_asset_id`
- rendering raw `media_type`
- rendering schema/debug/model labels
- hiding metadata by deleting the internal data needed for governed rendering

## Verification Requirement

Frontend widget tests and deterministic string audits must prove:

- editor UI does not expose internal media identifiers
- persisted preview UI does not expose internal media identifiers
- learner UI does not expose internal media identifiers
- renderer structure and media resolution are unchanged except for visible copy

## Execution Record

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

### Pre-Change Audit

- Editor media blocks rendered raw `mediaType` and `lessonMediaId`.
- Default preview fallback rendered raw media type, `lessonMediaId`, and raw
  state text.
- Course Editor persisted preview fell back to `mediaAssetId` for visible
  labels.
- Learner preview and learner media labels fell back to `mediaAssetId`.

### Materialized Outputs

- Replaced editor media block visible text with safe generic copy.
- Replaced default preview media visible text with safe generic copy.
- Removed `lessonMediaId` and raw state from default preview fallback.
- Removed Course Editor persisted preview `mediaAssetId` label fallback.
- Removed learner `mediaAssetId` label mapping and fallback.
- Added safe generic learner labels for image, audio, video, and document
  media.
- Added widget tests and no-leak assertions for editor, preview, and learner
  rendering.

### Verification Evidence

- `dart format lib\editor\document\lesson_document_editor.dart lib\features\studio\presentation\course_editor_page.dart lib\features\courses\presentation\lesson_page.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart test\widgets\lesson_media_pipeline_test.dart`
  completed for 6 files.
- `flutter analyze lib\editor\document\lesson_document_editor.dart lib\features\studio\presentation\course_editor_page.dart lib\features\courses\presentation\lesson_page.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart test\widgets\lesson_media_pipeline_test.dart`
  passed with `No issues found!`.
- `flutter test test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart test\widgets\lesson_media_pipeline_test.dart`
  passed: `28 passed`.
- Deterministic marker audit passed:
  `known user-facing leakage patterns removed`.

### Contract Preservation

- `lesson_document_v1` was not changed.
- Backend APIs were not changed.
- Internal media metadata remains available for lookup/rendering.
- Markdown, Quill, and legacy media-token pathways were not introduced.

### Next Deterministic Step

`LEMB-006 MEDIA BLOCK REGRESSION GATES`
