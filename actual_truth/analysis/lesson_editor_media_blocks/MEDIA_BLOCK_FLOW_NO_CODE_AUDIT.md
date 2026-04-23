# MEDIA BLOCK FLOW NO-CODE AUDIT

`input(task="Audit lesson editor media block positioning, rendering, and UI metadata leakage before DAG materialization", mode="read-only")`

## Status

AUDIT_STATUS: `COMPLETED`

Completed on: `2026-04-23`

This audit is no-code implementation evidence. It identifies the files and
decisions that must govern any later implementation of media-block insertion,
movement, rendering, and leakage cleanup in the rebuilt lesson editor.

## Authority Inputs

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/course_lesson_editor_contract.md`
- `actual_truth/contracts/lesson_editor_rebuild_manifest_contract.md`
- `actual_truth/contracts/media_pipeline_contract.md`
- `actual_truth/DETERMINED_TASKS/lesson_editor_rebuild/task_manifest.json`
- current repository code under `frontend/lib` and `frontend/test`

## Contract Boundary Finding

Active contract truth does not authorize `media_asset_id` as editor document
truth.

- `course_lesson_editor_contract.md` says lesson media document references
  must use typed media nodes that reference `lesson_media_id`.
- `lesson_editor_rebuild_manifest_contract.md` says media blocks carry
  `lesson_media_id` and `media_type`, and that `media_asset_id` is forbidden as
  editor document truth.
- `media_pipeline_contract.md` separates `media_asset_id` as ingest/asset
  identity from `lesson_media_id` as authored lesson placement identity.

Deterministic conclusion:

- Later implementation must keep `lesson_document_v1` media blocks keyed by
  `lesson_media_id`.
- If a future decision wants `media_asset_id` inside editor documents, that is
  a contract amendment task, not an implementation detail.

## A) Document Model Audit

Evidence:

- `frontend/lib/editor/document/lesson_document.dart:282` defines
  `LessonMediaBlock`.
- `frontend/lib/editor/document/lesson_document.dart:289` stores `mediaType`.
- `frontend/lib/editor/document/lesson_document.dart:290` stores
  `lessonMediaId`.
- `frontend/lib/editor/document/lesson_document.dart:299` serializes
  `media_type`.
- `frontend/lib/editor/document/lesson_document.dart:300` serializes
  `lesson_media_id`.
- `frontend/lib/editor/document/lesson_document.dart:366` stores document
  content as an ordered `List<LessonBlock>`.
- `frontend/lib/editor/document/lesson_document.dart:410` exposes
  `insertMedia(index, ...)`, which can insert at a requested block index.

Findings:

- Media is already modeled as a block-level `lesson_document_v1` node.
- Media is part of ordered document structure.
- The model has an index-based insert primitive, but no audited deterministic
  move operation was found for document blocks.
- The model uses `lesson_media_id`, not `media_asset_id`, as required by active
  contract law.

## B) Editor Behavior Audit

Evidence:

- `frontend/lib/features/studio/presentation/course_editor_page.dart:4349`
  defines `_insertMediaBlockIntoDocument`.
- `frontend/lib/features/studio/presentation/course_editor_page.dart:4353`
  calls `_lessonDocument.insertMedia(_lessonDocument.blocks.length, ...)`.
- `frontend/lib/features/studio/presentation/course_editor_page.dart:4380`,
  `4392`, `4403`, and `4413` route image, video, audio, and document insertion
  through the same append helper.
- `frontend/lib/features/studio/presentation/course_editor_page.dart:7558` and
  `7691` use `ReorderableListView.builder`, but these surfaces relate to
  course/lesson/media-list ordering, not document-block media movement.

Findings:

- Current Course Editor media insertion is append-only at the document tail.
- The current editor does not insert media at the active cursor/selection
  position.
- Deterministic media block reordering inside the document authoring surface
  needs implementation or explicit task rejection.
- Existing course/lesson/media placement reorder surfaces are not document AST
  block reorder controls.

## C) Rendering Layer Audit

Evidence:

- `frontend/lib/editor/document/lesson_document_editor.dart:750` defines
  `LessonDocumentPreview`.
- `frontend/lib/editor/document/lesson_document_editor.dart:779` maps preview
  media by `lessonMediaId`.
- `frontend/lib/editor/document/lesson_document_editor.dart:945` maps
  `LessonMediaBlock` to a preview media component.
- `frontend/lib/features/courses/presentation/lesson_page.dart:422` renders
  learner lesson content with `LessonDocumentPreview`.
- `frontend/lib/features/courses/presentation/lesson_page.dart:543` defines
  `_LearnerDocumentMediaBlock`.
- `frontend/test/widgets/lesson_media_pipeline_test.dart:336` contains the
  regression test that lesson media renders inline without trailing fallback
  duplication.

Findings:

- Preview and learner rendering already iterate document blocks in AST order.
- Media rendering is structurally inline when a media block appears in
  `document.blocks`.
- The main rendering gap is not append-outside-flow rendering. The main gap is
  that editor insertion places new media at the end, so authored order is often
  wrong before rendering.

## D) UI Metadata Leakage Audit

Evidence:

- `frontend/lib/editor/document/lesson_document_editor.dart:535` renders
  `Media: ${block.mediaType}` and `block.lessonMediaId` in the editor.
- `frontend/lib/editor/document/lesson_document_editor.dart:984` renders
  `Media: ${block.mediaType}` in the default preview fallback.
- `frontend/lib/editor/document/lesson_document_editor.dart:985` renders
  missing-media text containing raw media type.
- `frontend/lib/editor/document/lesson_document_editor.dart:1004` renders
  `block.lessonMediaId`.
- `frontend/lib/features/studio/presentation/course_editor_page.dart:1148`
  falls back from `media.originalName` to `media.mediaAssetId` for preview
  labels.
- `frontend/lib/features/courses/presentation/lesson_page.dart:332` maps learner
  preview media labels to `item.mediaAssetId`.
- `frontend/lib/features/courses/presentation/lesson_page.dart:630` through
  `633` returns `mediaAssetId` as a learner-visible media label fallback.

Findings:

- Current editor UI leaks internal media type and `lesson_media_id`.
- Current default preview fallback leaks internal media type and
  `lesson_media_id`.
- Studio preview and learner rendering can leak `media_asset_id` as a label
  when no safe display name exists.
- Later implementation must separate internal metadata from user-facing labels
  across editor, persisted preview, and learner view.

## Implementation-Affected Files

Likely implementation files:

- `frontend/lib/editor/document/lesson_document.dart`
- `frontend/lib/editor/document/lesson_document_editor.dart`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/features/courses/presentation/lesson_page.dart`

Likely test files:

- `frontend/test/unit/lesson_document_model_test.dart`
- `frontend/test/widgets/lesson_document_editor_test.dart`
- `frontend/test/widgets/lesson_preview_rendering_test.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`

Likely audit/gate files if enforcement is expanded:

- `tools/lesson_editor_authority_audit.py`
- `backend/tests/test_ler011_deterministic_audit_gates.py`
- `backend/tests/test_ler012_final_aggregate_editor_gate.py`

Contract files that should be treated as authority, not implementation targets,
unless a new decision explicitly amends them:

- `actual_truth/contracts/course_lesson_editor_contract.md`
- `actual_truth/contracts/lesson_editor_rebuild_manifest_contract.md`
- `actual_truth/contracts/media_pipeline_contract.md`

## Deterministic Task-Tree Input

The following implementation requirements are ready for DAG materialization:

- preserve `lesson_media_id` as the only editor document media reference
- add deterministic document block movement operations before UI movement
  controls depend on them
- replace append-only media insertion with cursor/selection-position insertion
- render media blocks inline from document AST order only
- remove user-visible internal identifiers and raw media-type/debug labels
- add regression gates proving insertion order, reordering, renderer parity, and
  no metadata leakage

## Stop Conditions For Later Implementation

Stop if implementation attempts to store `media_asset_id` in
`lesson_document_v1`.

Stop if media insertion bypasses document block order.

Stop if media rendering appends a separate media section outside the document
flow.

Stop if editor, preview, or learner UI renders `lesson_media_id`,
`media_asset_id`, raw `media_type`, or model/debug labels as user-facing copy.

Stop if Markdown, Quill, or legacy media-token pathways are reintroduced.
