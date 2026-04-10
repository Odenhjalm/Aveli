# CMTZ-001 BASELINE OWNERSHIP AND MONETIZATION FOUNDATION

- TYPE: `OWNER`
- GROUP: `BASELINE`

## Problem Statement

Verified repository state shows that course monetization code depends on canonical backend-owned course ownership, backend-owned Stripe mapping, and explicit sellability prerequisites, but those foundations are not evidenced consistently in the current baseline-backed schema surface.

This task establishes the canonical baseline-backed substrate required for single-owner course ownership as `app.courses.teacher_id -> app.auth_subjects.user_id`, backend-owned course monetization truth, and backend-owned bundle monetization truth without allowing Stripe, frontend, bundle ownership, tests, or runtime drift to become authority.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
  - `2. COURSE MONETIZATION AUTHORITY`
  - `3. PRICING AUTHORITY`
  - `4. SELLABLE MODEL`
  - `5. STRIPE PRODUCT MODEL`
  - `6. COURSE BUNDLE DOMAIN`
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

- `CMTZ-000`

## Acceptance Criteria

- baseline-backed canonical course ownership exists as `app.courses.teacher_id -> app.auth_subjects.user_id`
- canonical course ownership is single-owner only in MVP
- baseline-backed monetization state exists for backend-owned course Stripe mapping
- baseline-backed monetization state exists for backend-owned bundle Stripe mapping where missing or incomplete
- backend-owned explicit sellability substrate exists for courses and bundles
- `created_by` is forbidden as ownership authority
- ownership is not inferred from frontend, Stripe, bundle ownership, tests, or runtime drift
- no Stripe runtime state becomes authority
- no frontend or UI state becomes authority
- no membership authority is introduced into course or bundle monetization

## Stop Conditions

- stop if the proposed ownership substrate differs from `app.courses.teacher_id -> app.auth_subjects.user_id`
- stop if the proposed ownership model allows more than one canonical owner in MVP
- stop if `created_by` or any runtime drift is reused as ownership authority
- stop if ownership would be inferred from frontend, Stripe, bundle ownership, tests, or runtime drift
- stop if the proposed substrate would make Stripe authority
- stop if proposed substrate would make frontend or teacher UI authority
- stop if proposed substrate would merge course or bundle monetization into membership authority

## Out Of Scope

- endpoint implementation
- frontend alignment
- payout logic
- Stripe Connect
