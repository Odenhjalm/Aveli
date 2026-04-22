# CP-404_GUARD_VALIDATOR_OBSERVABILITY_HARDENING

- TYPE: `OWNER`
- TITLE: `Add guard and validator observability coverage`
- DOMAIN: `observability`
- CLASSIFICATION: `HARDEN`

## Problem Statement

Guard and validator failures remain hard to attribute when semantic drift is
distributed across multiple layers.

## Primary Authority Reference

- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `backend/app/services/courses_service.py`
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`

## Implementation Surfaces Affected

- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `backend/app/services/courses_service.py`
- `frontend/test`
- `backend/tests`

## DEPENDS_ON

- `CP-G03`

## Exact Implementation Steps

1. Expose observable failure reasons for frontend guard rejection.
2. Expose observable failure reasons for backend validator failure and
   validator-unavailable paths.
3. Keep observability bound to the owned boundary instead of creating fallback
   logic.

## Acceptance Criteria

- Save-boundary failures are attributable to one contract boundary.
- Regression gates can distinguish semantic mismatch from runtime unavailability.

## Stop Conditions

- Stop if observability requires introducing a second semantic owner.

## Out Of Scope

- Final aggregate readiness verification
