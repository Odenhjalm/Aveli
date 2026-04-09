# CMTZ-000 BUNDLE BASELINE FOUNDATION

- TYPE: `OWNER`
- GROUP: `BASELINE`

## Problem Statement

Verified repository state shows that bundle application flows already assume canonical bundle persistence, but the current baseline-backed schema authority does not yet materialize `app.course_bundles`.

This task materializes the minimal canonical baseline truth for `app.course_bundles` so later bundle monetization and sellability work has a real append-only baseline surface to extend.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
  - `6. COURSE BUNDLE DOMAIN`
  - `7. TEACHER SELLING EXPERIENCE LAW`
  - `9. MEMBERSHIP SEPARATION`
  - `10. MARKETPLACE COMPATIBILITY`
- [supabase_integration_boundary_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/supabase_integration_boundary_contract.md)
- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)
  - separation law for bundle commerce and membership authority

## Audit Inputs

- `CMA-07`
- `CMA-08`
- `CMA-16`

## Implementation Surfaces Affected

- `backend/supabase/baseline_slots/<future append-only slot for canonical course_bundles baseline>`
- `backend/supabase/baseline_slots.lock.json`

## Depends On

- none

## Acceptance Criteria

- replayed baseline includes `app.course_bundles`
- canonical bundle identity exists in baseline truth
- later tasks may safely extend bundle monetization fields append-only
- no membership authority is introduced
- no marketplace logic is introduced

## Stop Conditions

- stop if current contracts are insufficient to define minimal canonical bundle baseline truth

## Out Of Scope

- sellable fields
- Stripe mapping fields
- pricing logic
- frontend
- purchase flow
