# CP-G03_VALIDATION_PARITY_GATE

- TYPE: `GATE`
- TITLE: `Validation parity gate`
- DOMAIN: `cross-surface validation`
- CLASSIFICATION: `GATE`

## Problem Statement

Regression hardening cannot proceed until frontend guard and backend validator
agree on the same supported-content contract.

## Primary Authority Reference

- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- `frontend/test/unit/lesson_markdown_integrity_guard_test.dart`
- `backend/tests/test_lesson_markdown_validator.py`

## Implementation Surfaces Affected

- `frontend/lib/editor/guardrails/lesson_markdown_integrity_guard.dart`
- `backend/app/utils/lesson_markdown_validator.py`
- `frontend/test/unit/lesson_markdown_integrity_guard_test.dart`
- `backend/tests/test_lesson_markdown_validator.py`

## DEPENDS_ON

- `CP-201`
- `CP-202`

## Exact Implementation Steps

1. Run the locked supported fixtures through frontend and backend validation.
2. Confirm pass and fail verdicts match for the same fixture ids.
3. Fail closed if either side still owns comparison-only semantics.

## Acceptance Criteria

- Frontend guard and backend validator agree on the same supported-content
  corpus.

## Stop Conditions

- Stop on any split verdict for the same fixture id.

## Out Of Scope

- Render parity
