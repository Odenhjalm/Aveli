# LESSON EDITOR MEDIA BLOCKS DAG SUMMARY

## DAG

```text
LEMB-001
  -> LEMB-002
    -> LEMB-003
      -> LEMB-004
  -> LEMB-005

LEMB-003 + LEMB-004 + LEMB-005
  -> LEMB-006
    -> LEMB-007
```

## Node Semantics

| Task | Type | Status | Meaning |
| --- | --- | --- | --- |
| `LEMB-001` | `OWNER` | `COMPLETED` | Lock contract boundary: document media identity is `lesson_media_id`, not `media_asset_id`. |
| `LEMB-002` | `OWNER` | `COMPLETED` | Add deterministic document-model operations for inserting and moving blocks. |
| `LEMB-003` | `OWNER` | `COMPLETED` | Route Course Editor media insertion through cursor/selection document position instead of append-only insertion. |
| `LEMB-004` | `OWNER` | `COMPLETED` | Add deterministic media block move controls in the editor authoring UI. |
| `LEMB-005` | `OWNER` | `COMPLETED` | Remove user-facing internal media ids/types/debug labels from editor, preview, and learner surfaces. |
| `LEMB-006` | `GATE` | `COMPLETED` | Add regression gates for media ordering, renderer parity, and metadata no-leak behavior. |
| `LEMB-007` | `AGGREGATE` | `COMPLETED` | Run final aggregate gate for the media-block implementation slice. |

## Affected Implementation Surfaces

- `frontend/lib/editor/document/lesson_document.dart`
- `frontend/lib/editor/document/lesson_document_editor.dart`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/features/courses/presentation/lesson_page.dart`

## Affected Verification Surfaces

- `frontend/test/unit/lesson_document_model_test.dart`
- `frontend/test/widgets/lesson_document_editor_test.dart`
- `frontend/test/widgets/lesson_preview_rendering_test.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`
- `tools/lesson_editor_authority_audit.py`
- `backend/tests/test_ler011_deterministic_audit_gates.py`
- `backend/tests/test_ler012_final_aggregate_editor_gate.py`

## Execution Rule

No task may be marked completed until its task file contains:

- pre-change audit evidence
- materialized output summary
- verification command evidence
- explicit statement that `lesson_document_v1` and backend APIs were not
  modified outside the task's authority

## Post-DAG Amendment

On `2026-04-23`, media insertion UX was amended so newly inserted Course Editor
media blocks are inserted at document index `0` and then moved downward by the
user. This supersedes the earlier active-position insertion UX invariant while
preserving document-order movement and `lesson_document_v1`.
