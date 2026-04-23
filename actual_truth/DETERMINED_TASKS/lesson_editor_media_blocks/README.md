# LESSON_EDITOR_MEDIA_BLOCKS_TASK_TREE

`input(task="Materialize deterministic DAG task tree for lesson editor media blocks", mode="generate")`

## Scope

This task tree governs the next controlled implementation phase for media
blocks in the rebuilt lesson editor.

The implementation goal is:

- media blocks are inserted at document index `0` after the 2026-04-23
  post-DAG UX amendment
- media blocks can be moved deterministically inside document order
- preview and learner views render media inline from `lesson_document_v1`
  document order
- internal metadata is never rendered as user-facing UI
- no Markdown, Quill, or legacy media-token path is reintroduced

## Parent State

The parent editor rebuild DAG is closed through `LER-015`.

This tree depends on:

- `actual_truth/DETERMINED_TASKS/lesson_editor_rebuild/LER-015_reading_ux_modes.md`
- `actual_truth/analysis/lesson_editor_media_blocks/MEDIA_BLOCK_FLOW_NO_CODE_AUDIT.md`

## Controller Model

Current execution state:

- `LEMB-001`: `COMPLETED`
- `LEMB-002`: `COMPLETED`
- `LEMB-003`: `COMPLETED`
- `LEMB-004`: `COMPLETED`
- `LEMB-005`: `COMPLETED`
- `LEMB-006`: `COMPLETED`
- `LEMB-007`: `COMPLETED`

Next executable task:

- none; `lesson_editor_media_blocks` DAG is complete

The controller must:

- load `task_manifest.json`
- validate every task file exists
- execute tasks in topological order
- run retrieval before every task using that task's `retrieval_queries`
- perform a no-code pre-audit before file edits
- perform a post-change audit before marking a task completed
- record verification evidence in the task file before advancing
- stop on any contradiction between active contract truth and implementation

## Materialized Task Order

1. `LEMB-001` contract boundary lock
2. `LEMB-002` document operation primitives
3. `LEMB-003` cursor/selection-position media insertion
4. `LEMB-004` editor media block movement controls
5. `LEMB-005` renderer and UI metadata leakage cleanup
6. `LEMB-006` regression gates for order, parity, and no leakage
7. `LEMB-007` final aggregate media-block gate

## Contract Law

`lesson_document_v1` remains the only editor document authority.

Media blocks must use:

- `media_type`
- `lesson_media_id`

`media_asset_id` must remain outside editor document truth unless a future
contract-amendment task explicitly changes active law.

## Stop Conditions

Stop if any task stores `media_asset_id` in `lesson_document_v1`.

Stop if new Course Editor media insertion uses append fallback or active
cursor/selection insertion instead of document index `0`.

Stop if media rendering appends a separate trailing media section.

Stop if editor, preview, or learner UI renders `lesson_media_id`,
`media_asset_id`, raw `media_type`, schema labels, or debug labels as
user-facing copy.

Stop if Markdown, Quill, or legacy media-token pathways are reintroduced.

## Post-DAG Amendment

`actual_truth/analysis/lesson_editor_media_blocks/MEDIA_BLOCK_EDITOR_UX_REFINEMENT_20260423.md`
supersedes the earlier active-position insertion UX invariant for newly
inserted Course Editor media blocks.
