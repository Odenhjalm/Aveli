# CMTZ-007 SELLABLE COMPUTATION

- TYPE: `OWNER`
- GROUP: `SELLABLE COMPUTATION`

## Problem Statement

Verified repository state shows no explicit backend-computed `course.sellable` or `bundle.sellable`.
Current readiness is implicit and partially inferred from price presence, `is_active`, public listing behavior, and Stripe prerequisites.

This task introduces the contract-required backend-computed sellability model.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
  - `2. COURSE MONETIZATION AUTHORITY`
  - `4. SELLABLE MODEL`
  - `7. TEACHER SELLING EXPERIENCE LAW`
  - `11. FAILURE MODEL`
  - `12. FORBIDDEN PATTERNS`

## Audit Inputs

- `CMA-04`
- `CMA-08`
- `CMA-13`

## Implementation Surfaces Affected

- `backend/app/services/courses_service.py`
- `backend/app/services/course_bundles_service.py`
- `backend/app/routes/courses.py`
- `backend/app/routes/course_bundles.py`
- `backend/app/repositories/*`

## Depends On

- `CMTZ-001`
- `CMTZ-002`
- `CMTZ-003`
- `CMTZ-005`
- `CMTZ-006`

## Acceptance Criteria

- `course.sellable` is backend-computed
- `bundle.sellable` is backend-computed
- sellability is not inferred from frontend UI state
- sellability is not inferred from Stripe runtime state
- public discovery and purchase gating consume canonical sellability
- `published_only` or similar discovery hints do not bypass canonical sellability

## Stop Conditions

- stop if sellability is still implicit
- stop if Stripe success or Stripe existence alone makes an item sellable
- stop if teacher UI `is_active` or similar local state remains hidden authority

## Out Of Scope

- frontend redesign
- test gate implementation
- membership access logic
