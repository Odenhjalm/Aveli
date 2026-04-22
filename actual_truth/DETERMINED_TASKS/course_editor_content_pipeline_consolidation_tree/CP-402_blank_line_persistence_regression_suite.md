# CP-402_BLANK_LINE_PERSISTENCE_REGRESSION_SUITE

- TYPE: `OWNER`
- TITLE: `Pin the blank-line persistence regression suite`
- DOMAIN: `regression coverage`
- CLASSIFICATION: `PIN`

## Problem Statement

Blank-line persistence remains an active defect and must be pinned across the
full supported-content path before the pipeline can be considered stable.

## Primary Authority Reference

- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- `frontend/test/unit/lesson_newline_persistence_test.dart`
- `backend/tests/test_lesson_newline_persistence.py`

## Implementation Surfaces Affected

- `frontend/test/unit/lesson_newline_persistence_test.dart`
- `backend/tests/test_lesson_newline_persistence.py`
- `frontend/test/widgets/lesson_preview_rendering_test.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`

## DEPENDS_ON

- `CP-G03`
- `CP-G04`

## Exact Implementation Steps

1. Bind the newline regression suite to the locked blank-line fixture ids.
2. Cover adapter roundtrip, backend write persistence, preview, and learner
   render.
3. Fail closed if any layer collapses an intentional paragraph break.

## Acceptance Criteria

- Blank-line persistence is pinned across unit, backend, and render surfaces.

## Stop Conditions

- Stop if any layer still rewrites the canonical newline fixtures differently.

## Out Of Scope

- EOF italic coverage
