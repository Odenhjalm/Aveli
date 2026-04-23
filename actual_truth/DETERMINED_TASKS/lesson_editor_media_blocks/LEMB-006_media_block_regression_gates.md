# LEMB-006 MEDIA BLOCK REGRESSION GATES

TYPE: `GATE`
TASK_TYPE: `MEDIA_BLOCK_REGRESSION_GATES`
DEPENDS_ON: `[LEMB-003, LEMB-004, LEMB-005]`

## Goal

Add deterministic regression gates that prevent media-block ordering,
renderer-parity, or UI-metadata leakage regressions.

## Required Outputs

- positive fixture/test coverage for image, audio, video, and document media
  blocks inside text flow
- tests proving media insertion uses active position
- tests proving media block movement preserves document shape and changes only
  order
- tests proving preview and learner render identical document structure order
- no-leak checks for `lesson_media_id`, `media_asset_id`, raw `media_type`, and
  debug/model labels in user-facing widget output

## Target Files

- `frontend/test/unit/lesson_document_model_test.dart`
- `frontend/test/widgets/lesson_document_editor_test.dart`
- `frontend/test/widgets/lesson_preview_rendering_test.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`
- `tools/lesson_editor_authority_audit.py`
- `backend/tests/test_ler011_deterministic_audit_gates.py`
- `backend/tests/test_ler012_final_aggregate_editor_gate.py`

## Retrieval Queries

- `lesson_document_fixture_corpus media blocks image audio video document`
- `lesson_media_pipeline_test inline document tokens trailing fallback`
- `lesson_editor_authority_audit forbidden rendered labels`
- `LER-011 deterministic audit gates media metadata leak`

## Forbidden

- replacing assertions with snapshots that tolerate id leakage
- removing existing inline-rendering tests without replacement
- testing only append-at-end insertion
- treating backend media placement reorder as document AST movement

## Verification Requirement

The task may complete only after the focused frontend tests and deterministic
authority/audit gates fail on forbidden media metadata leakage and pass on the
new expected behavior.

## Execution Record

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

### Pre-Change Audit

- Existing frontend tests already covered media insertion order, movement, inline
  preview/learner rendering, and UI no-leak behavior.
- Missing authority was in deterministic backend audit gates and final aggregate
  enforcement.
- `tools/lesson_editor_authority_audit.py` already had the required source-block
  and token-finding helpers, so no tool change was required.

### Materialized Outputs

- Added seeded LER-011 detection for append-only media insertion, raw media
  labels, and `mediaAssetId` label fallback.
- Added LER-011 source gates for positioned insertion, editor move controls,
  document move primitives, and user-facing no-leak behavior.
- Extended LER-012 final aggregate gate so LEMB-specific behavior and LER-011
  gate functions must remain present.
- Preserved existing frontend regression tests for image, audio, video, and
  document media blocks in document flow.

### Verification Evidence

- `.\.venv\Scripts\python.exe -m pytest backend\tests\test_ler011_deterministic_audit_gates.py backend\tests\test_ler012_final_aggregate_editor_gate.py`
  passed: `21 passed`.
- `flutter analyze lib\editor\document\lesson_document.dart lib\editor\document\lesson_document_editor.dart lib\features\studio\presentation\course_editor_page.dart lib\features\courses\presentation\lesson_page.dart test\unit\lesson_document_model_test.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart test\widgets\lesson_media_pipeline_test.dart`
  passed: `No issues found!`.
- `flutter test test\unit\lesson_document_model_test.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart test\widgets\lesson_media_pipeline_test.dart`
  passed: `42 passed`.
- Manifest validation passed:
  `validated 7 tasks; LEMB-001..006 completed; next LEMB-007`.
- `git diff --check` passed with no whitespace errors.

### Contract Preservation

- `lesson_document_v1` was not changed.
- Backend APIs were not changed.
- Internal media metadata remains available for governed lookup and rendering.
- User-facing metadata leakage, append-only insertion, Markdown, Quill, and
  legacy media-token paths remain forbidden by deterministic gates.

### Analysis Record

`actual_truth/analysis/lesson_editor_media_blocks/MEDIA_BLOCK_REGRESSION_GATES_LEMB006.md`

### Next Deterministic Step

`LEMB-007 FINAL MEDIA BLOCK GATE`
