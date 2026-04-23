# LEMB-001 CONTRACT BOUNDARY LOCK

TYPE: `OWNER`
TASK_TYPE: `CONTRACT_BOUNDARY_LOCK`
DEPENDS_ON: `[]`

## Goal

Lock the media-block implementation boundary before any code change.

The task must confirm that the editor document model uses
`lesson_media_id` as authored placement identity and must reject
`media_asset_id` as editor document truth unless active contracts are amended
first.

## Required Outputs

- confirm active contract law for media block identity
- document the conflict between the requested `media_asset_id` expectation and
  active contract law
- define the implementation rule for later tasks:
  `LessonMediaBlock(media_type, lesson_media_id)` remains the canonical editor
  document node
- identify every code path that may use `media_asset_id` only as read-only
  placement/asset metadata, not document truth

## Target Files

- `actual_truth/contracts/course_lesson_editor_contract.md`
- `actual_truth/contracts/lesson_editor_rebuild_manifest_contract.md`
- `actual_truth/contracts/media_pipeline_contract.md`
- `actual_truth/analysis/lesson_editor_media_blocks/MEDIA_BLOCK_FLOW_NO_CODE_AUDIT.md`
- `frontend/lib/editor/document/lesson_document.dart`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/features/courses/presentation/lesson_page.dart`

## Retrieval Queries

- `lesson_document_v1 media block lesson_media_id media_asset_id contract`
- `LessonMediaBlock media_type lessonMediaId serialization`
- `media_pipeline_contract media_asset_id lesson_media_id identity boundary`
- `course_lesson_editor_contract lesson media document references`

## Forbidden

- changing `lesson_document_v1` to store `media_asset_id`
- weakening media pipeline identity separation
- treating repository drift as contract truth
- reintroducing Markdown or Quill media tokens

## Verification Requirement

The task may complete only after the execution record proves:

- active contracts still require `lesson_media_id`
- no implementation output stores `media_asset_id` in the editor document AST
- later implementation tasks have a clear stop condition for identity
  contradiction

## Execution Record

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

### Audit Evidence

- Active contract law was re-read from
  `actual_truth/contracts/course_lesson_editor_contract.md`,
  `actual_truth/contracts/lesson_editor_rebuild_manifest_contract.md`, and
  `actual_truth/contracts/media_pipeline_contract.md`.
- Repository evidence was re-read from
  `frontend/lib/editor/document/lesson_document.dart`,
  `frontend/lib/features/studio/presentation/course_editor_page.dart`, and
  `frontend/lib/features/courses/presentation/lesson_page.dart`.
- The prior no-code audit
  `actual_truth/analysis/lesson_editor_media_blocks/MEDIA_BLOCK_FLOW_NO_CODE_AUDIT.md`
  was used as supporting evidence.

### Locked Decision

`LessonMediaBlock(media_type, lesson_media_id)` remains the canonical
`lesson_document_v1` media node.

`media_asset_id` remains pipeline/asset/placement metadata only and must not be
stored in editor document truth.

### Materialized Output

- Added
  `actual_truth/analysis/lesson_editor_media_blocks/CONTRACT_BOUNDARY_LOCK_LEMB001.md`.
- Added
  `actual_truth/DETERMINED_TASKS/lesson_editor_media_blocks/FULL_CHAIN_CONTROLLED_EXCAVATION_BATCHES.md`.
- Updated this task record from `PENDING` to `COMPLETED`.

### Verification Evidence

- Contract evidence confirms active law still requires `lesson_media_id`.
- `frontend/lib/editor/document/lesson_document.dart` stores and serializes
  media blocks as `mediaType` / `lessonMediaId`,
  `media_type` / `lesson_media_id`.
- `media_asset_id` usage in Course Editor and learner code is classified as
  read metadata or UI leakage, not editor document truth. The leakage cleanup
  remains assigned to `LEMB-005`.

### Next Deterministic Step

`LEMB-002 DOCUMENT OPERATION PRIMITIVES`
