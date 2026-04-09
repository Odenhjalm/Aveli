# CMTZ-001 BASELINE MONETIZATION FOUNDATION

- TYPE: `OWNER`
- GROUP: `BASELINE`

## Problem Statement

Verified repository state shows that course monetization code depends on backend-owned Stripe mapping and sellability prerequisites, but those foundations are not evidenced consistently in the current baseline-backed schema surface.

This task establishes the canonical baseline-backed substrate required for backend-owned course and bundle monetization truth without allowing Stripe, frontend, or UI state to become authority.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
  - `2. COURSE MONETIZATION AUTHORITY`
  - `4. SELLABLE MODEL`
  - `5. STRIPE PRODUCT MODEL`
- [supabase_integration_boundary_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/supabase_integration_boundary_contract.md)
- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)
  - separation law for orders and payments

## Audit Inputs

- `CMA-03`
- `CMA-04`
- `CMA-08`
- `CMA-14`

## Implementation Surfaces Affected

- `backend/supabase/baseline_slots/*`
- `backend/supabase/baseline_slots.lock.json`

## Depends On

- none

## Acceptance Criteria

- baseline-backed monetization state exists for backend-owned course Stripe mapping
- baseline-backed monetization state exists for backend-owned bundle Stripe mapping where missing or incomplete
- backend-owned explicit sellability substrate exists for courses and bundles
- no Stripe runtime state becomes authority
- no frontend or UI state becomes authority
- no membership authority is introduced into course or bundle monetization

## Stop Conditions

- stop if the proposed substrate would make Stripe authority
- stop if proposed substrate would make frontend or teacher UI authority
- stop if proposed substrate would merge course or bundle monetization into membership authority

## Out Of Scope

- endpoint implementation
- frontend alignment
- payout logic
- Stripe Connect
