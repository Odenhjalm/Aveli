# CMTZ-002 TEACHER PRICING AUTHORITY

- TYPE: `OWNER`
- GROUP: `PRICING AUTHORITY`

## Problem Statement

Verified current state shows that course price editing exists in the teacher UI and persists via studio routes, but ownership validation is not consistently enforced and the runtime teacher course creation experience is incomplete.

This task aligns teacher pricing to the contract by making backend validation and teacher ownership the only authority for course pricing intent.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
  - `3. PRICING AUTHORITY`
  - `7. TEACHER SELLING EXPERIENCE LAW`
  - `11. FAILURE MODEL`
  - `12. FORBIDDEN PATTERNS`
- [supabase_integration_boundary_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/supabase_integration_boundary_contract.md)

## Audit Inputs

- `CMA-05`
- `CMA-11`

## Implementation Surfaces Affected

- `backend/app/routes/studio.py`
- `backend/app/services/*`
- `backend/app/repositories/courses.py`
- `frontend/lib/features/studio/*`

## Depends On

- `CMTZ-001`

## Acceptance Criteria

- teacher pricing changes require canonical course ownership
- backend validates and persists pricing intent
- frontend remains intent-only and projection-only
- mounted teacher selling flow supports canonical price submission without frontend authority
- completed purchases remain price-immutable
- no admin or teacher action rewrites historical purchase truth

## Stop Conditions

- stop if teacher UI becomes price authority
- stop if ownership checks can still be bypassed
- stop if price history would be mutated for completed purchases

## Out Of Scope

- Stripe product creation
- bundle pricing
- checkout flow repair
