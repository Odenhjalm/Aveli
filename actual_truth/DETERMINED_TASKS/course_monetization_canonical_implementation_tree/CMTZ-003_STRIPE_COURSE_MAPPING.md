# CMTZ-003 STRIPE COURSE MAPPING

- TYPE: `OWNER`
- GROUP: `STRIPE COURSE MAPPING`

## Problem Statement

Verified repository state shows that course checkout already depends on backend-owned course Stripe assets, but the code path references missing orchestration and currently relies on mapping expectations not evidenced consistently in baseline-backed state.

This task creates the canonical backend-owned course-to-Stripe mapping path required by the contract.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
  - `2. COURSE MONETIZATION AUTHORITY`
  - `5. STRIPE PRODUCT MODEL`
  - `8. PURCHASE FLOW`
  - `12. FORBIDDEN PATTERNS`
- [supabase_integration_boundary_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/supabase_integration_boundary_contract.md)

## Audit Inputs

- `CMA-03`
- `CMA-14`

## Implementation Surfaces Affected

- `backend/app/services/checkout_service.py`
- `backend/app/services/courses_service.py`
- `backend/app/repositories/courses.py`
- baseline-backed monetization substrate from `CMTZ-001`

## Depends On

- `CMTZ-001`
- `CMTZ-002`

## Acceptance Criteria

- each sellable course maps to one backend-owned Stripe product and one active Stripe price at a time
- new price changes create new Stripe prices for future purchases only
- historical purchase records remain tied to original order/payment truth
- checkout no longer depends on missing or ad hoc Stripe orchestration
- Stripe remains infrastructure only and never becomes monetization authority

## Stop Conditions

- stop if Stripe runtime state becomes course truth
- stop if frontend state participates in Stripe mapping authority
- stop if course checkout can proceed without canonical backend mapping

## Out Of Scope

- bundle Stripe mapping
- frontend selling flow
- membership logic
