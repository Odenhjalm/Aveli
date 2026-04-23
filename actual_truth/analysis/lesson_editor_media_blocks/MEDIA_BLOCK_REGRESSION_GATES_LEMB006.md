# MEDIA BLOCK REGRESSION GATES LEMB-006

`input(task="Execute LEMB-006 media block regression gates", mode="code")`

## Status

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

## Pre-Change Audit

Existing frontend coverage already proved the current implementation behavior:

- media blocks can be inserted before, between, and after text blocks
- media block movement changes document order without changing block payloads
- editor media insertion uses an active document position instead of
  unconditional append
- preview and learner surfaces render media inline from `lesson_document_v1`
- widget assertions cover no visible `lesson_media_id`, `media_asset_id`, raw
  `media_type`, or debug/model labels

The gap was gate-level authority. Backend deterministic audit tests did not yet
lock the media-block regressions directly, and the final aggregate editor gate
did not yet require those LEMB-specific gates.

## Materialized Output

Updated `backend/tests/test_ler011_deterministic_audit_gates.py`:

- added a seeded regression test proving forbidden media-block patterns are
  detected:
  - append-only insertion via `_lessonDocument.blocks.length`
  - rendered `block.mediaType`
  - rendered `block.lessonMediaId`
  - `mediaAssetId` label fallback
  - learner label fallback returning `mediaAssetId`
- added a source gate proving Course Editor media insertion uses
  `_resolvedLessonDocumentInsertionIndex()`
- added a source gate proving editor movement delegates to
  `LessonDocument.moveBlock`
- added a source gate proving document move primitives remain present
- added a no-leak source gate for editor, persisted preview, and learner media
  labels

Updated `backend/tests/test_ler012_final_aggregate_editor_gate.py`:

- final aggregate now requires top media insertion at document index `0`
- final aggregate now rejects append-only media insertion
- final aggregate now requires document move primitives and editor move
  delegation
- final aggregate now rejects user-facing media metadata leakage
- final aggregate now requires safe media copy and learner labels
- final aggregate now requires the LER-011 LEMB-specific gate functions to
  exist

`tools/lesson_editor_authority_audit.py` was inspected and left unchanged
because existing helpers already support the required deterministic token and
source-block gates.

## Gate Calibration

The first aggregate gate pass was intentionally strict and caught that
`block.lessonMediaId` still appears in legitimate internal learner lookup code.
The gate was corrected to forbid rendered interpolation
`${block.lessonMediaId}` rather than valid internal document-resolution use.

This preserves the contract boundary:

- internal metadata remains available for governed rendering
- internal metadata is not shown as user-facing copy

## Contract Preservation

`lesson_document_v1` remains unchanged.

Backend APIs remain unchanged.

No Markdown, Quill, legacy media-token path, raw media URL authority, or
`media_asset_id` document authority was introduced.

## Verification Evidence

Commands:

```text
.\.venv\Scripts\python.exe -m pytest backend\tests\test_ler011_deterministic_audit_gates.py backend\tests\test_ler012_final_aggregate_editor_gate.py
flutter analyze lib\editor\document\lesson_document.dart lib\editor\document\lesson_document_editor.dart lib\features\studio\presentation\course_editor_page.dart lib\features\courses\presentation\lesson_page.dart test\unit\lesson_document_model_test.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart test\widgets\lesson_media_pipeline_test.dart
flutter test test\unit\lesson_document_model_test.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart test\widgets\lesson_media_pipeline_test.dart
manifest validation for actual_truth/DETERMINED_TASKS/lesson_editor_media_blocks/task_manifest.json
git diff --check
```

Results:

- deterministic backend audit gates passed: `21 passed`
- focused Flutter analyze passed: `No issues found!`
- focused Flutter model/widget/media tests passed: `42 passed`
- manifest validation passed: `validated 7 tasks; LEMB-001..006 completed; next LEMB-007`
- `git diff --check` passed with no whitespace errors

## Deterministic Result

`LEMB-006` converts the media-block behavior from implementation-only coverage
into deterministic regression gates. Append-only media insertion, document-order
movement drift, missing LEMB audit gates, and user-facing media metadata leakage
are now blocked by focused gates and the final aggregate editor gate.

## Next Deterministic Step

`LEMB-007 FINAL MEDIA BLOCK GATE`
