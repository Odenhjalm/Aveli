# CP-401_PREVIEW_AUTHORITY_REGRESSION_DRIFT_REPAIR

- TYPE: `OWNER`
- TITLE: `Repair the preview-authority regression drift test`
- DOMAIN: `test drift`
- CLASSIFICATION: `REPAIR`

## Problem Statement

The current backend preview-authority regression test is stale and can no longer
be trusted as a deterministic authority gate.

## Primary Authority Reference

- `backend/tests/test_write_path_dominance_regression.py`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`

## Implementation Surfaces Affected

- `backend/tests/test_write_path_dominance_regression.py`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`

## DEPENDS_ON

- `CP-302`

## Exact Implementation Steps

1. Repoint the regression test to current preview-authority code structure.
2. Verify persisted preview authority without helper-name trivia.
3. Keep the test scoped to authority behavior, not refactor-sensitive source
   strings.

## Acceptance Criteria

- The preview-authority regression test asserts current persisted-preview
  behavior and is stable under benign refactors.

## Stop Conditions

- Stop if preview authority cannot be expressed without brittle source-string
  coupling.

## Out Of Scope

- Blank-line and EOF regression suites
