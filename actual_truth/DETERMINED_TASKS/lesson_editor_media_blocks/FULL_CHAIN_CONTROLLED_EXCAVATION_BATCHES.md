# FULL CHAIN CONTROLLED EXCAVATION BATCHES

`input(task="Propose controlled full-chain excavation batches for lesson editor media block DAG", mode="generate")`

## Status

BATCH_PLAN_STATUS: `COMPLETED`

Created on: `2026-04-23`

This plan sequences the pending `LEMB-*` tasks into controlled implementation
batches. It is intentionally conservative: each batch has one primary mutation
axis and its own audit and verification gate.

## Batch 0 - Boundary Lock

Tasks:

- `LEMB-001`

Status:

- `COMPLETED`

Purpose:

- lock `lesson_media_id` as editor document media identity
- keep `media_asset_id` outside `lesson_document_v1`

Exit gate:

- `CONTRACT_BOUNDARY_LOCK_LEMB001.md` exists and records completed boundary
  evidence

## Batch 1 - Document Operation Substrate

Tasks:

- `LEMB-002`

Status:

- `COMPLETED`

Purpose:

- add deterministic document operation primitives before UI code depends on
  them
- keep movement as pure document-order transformation

Mutation scope:

- `frontend/lib/editor/document/lesson_document.dart`
- `frontend/test/unit/lesson_document_model_test.dart`

Required verification:

- focused Dart unit tests for insertion and movement
- JSON serialization shape still emits `media_type` and `lesson_media_id`
- no `media_asset_id` or `mediaAssetId` appears in the document model

Stop if:

- movement mutates payload content instead of only block order
- any operation changes schema version or backend API shape

## Batch 2 - Positioned Authoring Insertion

Tasks:

- `LEMB-003`

Status:

- `COMPLETED`

Purpose:

- replace append-only Course Editor media insertion with active-position
  insertion
- connect editor selection/cursor state to document insertion index

Mutation scope:

- `frontend/lib/editor/document/lesson_document_editor.dart`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/test/widgets/lesson_document_editor_test.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`

Required verification:

- widget tests for insert between text blocks
- widget tests for insert after focused/cursor block
- preview receives the same block order as editor state
- existing inline-rendering/no-trailing-fallback test remains passing

Stop if:

- `_lessonDocument.blocks.length` remains the unconditional insertion target
- media is rendered or stored outside `document.blocks`

## Batch 3 - Media Block Movement Controls

Tasks:

- `LEMB-004`

Status:

- `COMPLETED`

Purpose:

- expose controlled move up/down actions for media blocks inside the
  continuous writing surface
- keep controls deterministic and boundary-safe

Mutation scope:

- `frontend/lib/editor/document/lesson_document_editor.dart`
- `frontend/test/widgets/lesson_document_editor_test.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`

Required verification:

- moving media up/down changes only block order
- boundary moves are disabled or deterministic no-ops
- preview order matches editor order after movement
- controls do not expose internal ids or raw media types

Stop if:

- media movement uses lesson-media placement reorder APIs
- UI movement bypasses document-model operations
- visible per-block container styling regresses the continuous surface

## Batch 4 - UI Metadata No-Leak Cleanup

Tasks:

- `LEMB-005`

Status:

- `COMPLETED`

Purpose:

- remove internal media identifiers and raw metadata from editor, preview, and
  learner user-facing UI
- keep internal metadata available for governed resolution only

Mutation scope:

- `frontend/lib/editor/document/lesson_document_editor.dart`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/features/courses/presentation/lesson_page.dart`
- `frontend/test/widgets/lesson_document_editor_test.dart`
- `frontend/test/widgets/lesson_preview_rendering_test.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`

Required verification:

- widget tests prove no visible `lesson_media_id`
- widget tests prove no visible `media_asset_id`
- widget tests prove no raw `media_type`/debug/model labels
- media rendering still resolves by internal metadata

Stop if:

- no-leak cleanup deletes internal metadata needed for media resolution
- fallback copy exposes ids, schema names, or technical type labels

## Batch 5 - Regression Gates

Tasks:

- `LEMB-006`

Status:

- `COMPLETED`

Purpose:

- encode the behavior from batches 1-4 as deterministic regression gates
- prevent silent return of append-only insertion, order drift, or metadata
  leakage

Mutation scope:

- `frontend/test/unit/lesson_document_model_test.dart`
- `frontend/test/widgets/lesson_document_editor_test.dart`
- `frontend/test/widgets/lesson_preview_rendering_test.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`
- `tools/lesson_editor_authority_audit.py`
- `backend/tests/test_ler011_deterministic_audit_gates.py`
- `backend/tests/test_ler012_final_aggregate_editor_gate.py`

Required verification:

- focused Flutter test suite passes
- deterministic audit gate fails on forbidden patterns and passes current
  implementation
- fixture coverage includes image, audio, video, and document media blocks

Stop if:

- tests only cover tail insertion
- no-leak assertions are snapshot-only or optional

## Batch 6 - Final Aggregate Gate

Tasks:

- `LEMB-007`

Status:

- `COMPLETED`

Purpose:

- close the media-block implementation slice with full-chain evidence

Mutation scope:

- execution records under `actual_truth/analysis/lesson_editor_media_blocks`
- execution records under `actual_truth/DETERMINED_TASKS/lesson_editor_media_blocks`
- focused frontend and audit-gate files touched by prior batches

Required verification:

- focused `flutter analyze` for touched frontend files
- focused Flutter unit/widget tests for media-block behavior
- deterministic backend audit gates for forbidden legacy/media leakage patterns
- manifest JSON validation
- task-file and dependency validation

Stop if:

- any pending `LEMB-*` task lacks execution evidence
- any active contract contradiction remains unresolved
- Markdown, Quill, or legacy media tokens reappear as editor authority

## Recommended Execution Strategy

Execute one batch at a time.

After every batch:

- update the corresponding `LEMB-*` task execution record
- update `task_manifest.json` status for completed tasks
- rerun manifest validation
- record verification evidence before proceeding

Do not combine Batch 1 with Batch 2. The document operation substrate must be
stable before the editor authoring surface depends on it.

Batch 3 and Batch 4 can be implemented separately and verified independently
after Batch 2. If time pressure requires grouping, group them only after Batch 2
passes and keep their test gates separate.
