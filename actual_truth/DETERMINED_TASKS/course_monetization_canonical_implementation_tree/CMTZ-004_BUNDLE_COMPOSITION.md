# CMTZ-004 BUNDLE COMPOSITION

- TYPE: `OWNER`
- GROUP: `BUNDLE COMPOSITION`

## Problem Statement

Verified repository state shows that bundle composition already exists and validates teacher ownership when courses are attached, but these invariants must be locked to the new contract so bundle composition stays same-teacher, course-only, and membership-separated.

This task preserves the correct bundle composition behavior and seals the remaining composition invariants.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
  - `6. COURSE BUNDLE DOMAIN`
  - `7. TEACHER SELLING EXPERIENCE LAW`
  - `11. FAILURE MODEL`
- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)
  - bundle separation and membership separation law

## Audit Inputs

- `CMA-07`
- `CMA-16`

## Implementation Surfaces Affected

- `backend/app/routes/course_bundles.py`
- `backend/app/services/course_bundles_service.py`
- `backend/app/repositories/course_bundles.py`

## Depends On

- none

## Acceptance Criteria

- all courses in a bundle must belong to the same teacher
- full step-series bundles are supported
- mixed-course-group bundles are supported only within same-teacher ownership
- bundle fulfillment remains course-enrollment only
- bundle flow never mutates membership

## Stop Conditions

- stop if cross-teacher bundles are introduced in MVP
- stop if bundle composition can infer or mutate membership
- stop if bundle ownership can be bypassed

## Out Of Scope

- bundle Stripe mapping
- bundle sellability
- student-facing checkout UX
