# CMTZ-010 LEGACY REMOVAL

- TYPE: `OWNER`
- GROUP: `LEGACY REMOVAL`

## Problem Statement

Verified repository state still contains redundant or non-canonical residue, including overlapping studio course route exposure, stale polymorphic checkout schema artifacts, and discovery behavior that does not align to canonical sellability.

This task removes or isolates those legacy surfaces only after canonical replacements exist.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
  - `4. SELLABLE MODEL`
  - `7. TEACHER SELLING EXPERIENCE LAW`
  - `12. FORBIDDEN PATTERNS`
- [supabase_integration_boundary_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/supabase_integration_boundary_contract.md)

## Audit Inputs

- `CMA-06`
- `CMA-12`
- `CMA-13`

## Implementation Surfaces Affected

- `backend/app/routes/studio.py`
- `backend/app/schemas/checkout.py`
- `backend/app/services/courses_service.py`
- `frontend/lib/*` only if legacy UI surfaces remain after canonical alignment

## Depends On

- `CMTZ-002`
- `CMTZ-003`
- `CMTZ-007`
- `CMTZ-009`

## Acceptance Criteria

- overlapping or redundant studio course route behavior is removed or isolated
- stale polymorphic checkout schema residue is removed
- public discovery no longer bypasses canonical sellability
- no legacy surface can reintroduce frontend or Stripe authority

## Stop Conditions

- stop if legacy removal would break canonical selling flow
- stop if removal would break bundle separation or membership separation
- stop if canonical replacements are not already live

## Out Of Scope

- new feature introduction
- payout logic
- marketplace logic
