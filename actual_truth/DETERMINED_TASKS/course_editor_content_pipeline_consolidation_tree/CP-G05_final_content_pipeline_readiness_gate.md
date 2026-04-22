# CP-G05_FINAL_CONTENT_PIPELINE_READINESS_GATE

- TYPE: `AGGREGATE`
- TITLE: `Final content-pipeline readiness gate`
- DOMAIN: `aggregate verification`

## Problem Statement

The content pipeline is aligned only when blocker semantics, adapter ownership,
validation parity, render parity, regression coverage, and observability all
point to the same Markdown-canonical truth.

## Primary Authority Reference

- `actual_truth/contracts/course_lesson_editor_contract.md`
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- `actual_truth/DETERMINED_TASKS/course_editor_content_pipeline_consolidation_tree/task_manifest.json`

## Implementation Surfaces Affected

- `frontend/lib/editor/adapter`
- `frontend/lib/editor/guardrails/lesson_markdown_integrity_guard.dart`
- `frontend/lib/shared/utils/lesson_content_pipeline.dart`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/features/courses/presentation/lesson_page.dart`
- `backend/app/utils/lesson_markdown_validator.py`
- `backend/app/services/courses_service.py`
- `frontend/test`
- `backend/tests`

## DEPENDS_ON

- `CP-401`
- `CP-402`
- `CP-403`
- `CP-404`

## Exact Implementation Steps

1. Re-run contract-scoped verification for blocker semantics, adapter
   ownership, validation parity, and render parity.
2. Confirm preview-authority drift, blank-line regressions, EOF italic
   regressions, and observability coverage are all closed.
3. Emit a final PASS or FAIL result for the content-pipeline consolidation
   cluster and stop.

## Acceptance Criteria

- No competing content-pipeline semantic owner remains.
- Preview and learner surfaces prove parity for the supported subset.
- Validation and regression gates all align to the same canonical truth.

## Stop Conditions

- Stop on any surviving blocker, parity mismatch, regression failure, or
  observability gap.

## Out Of Scope

- New architecture decisions
- Schema or API migration work
