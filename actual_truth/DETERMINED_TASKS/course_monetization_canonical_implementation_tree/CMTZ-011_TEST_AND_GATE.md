# CMTZ-011 TEST AND GATE

- TYPE: `AGGREGATE`
- GROUP: `TEST + GATE`

## Problem Statement

Course Monetization and Teacher Pricing need final contract gates so the repaired system cannot regress into frontend authority, Stripe authority, implicit sellability, membership leakage, or non-canonical bundle behavior.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
  - all sections
- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)
  - separation and order/payment authority law
- [supabase_integration_boundary_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/supabase_integration_boundary_contract.md)

## Audit Inputs

- `CMA-01`
- `CMA-02`
- `CMA-03`
- `CMA-04`
- `CMA-05`
- `CMA-06`
- `CMA-07`
- `CMA-08`
- `CMA-09`
- `CMA-10`
- `CMA-11`
- `CMA-12`
- `CMA-13`
- `CMA-14`
- `CMA-15`
- `CMA-16`

## Implementation Surfaces Affected

- `backend/tests/*`
- frontend verification surfaces
- any contract gate or regression test layer added for monetization

## Depends On

- `CMTZ-000`
- `CMTZ-001`
- `CMTZ-002`
- `CMTZ-003`
- `CMTZ-004`
- `CMTZ-005`
- `CMTZ-006`
- `CMTZ-007`
- `CMTZ-008`
- `CMTZ-009`
- `CMTZ-010`

## Acceptance Criteria

- course pricing authority is backend-only
- bundle pricing authority is backend-only
- course sellability is backend-computed
- bundle sellability is backend-computed
- course Stripe mapping is backend-owned and deterministic
- bundle Stripe mapping is backend-owned and deterministic
- course purchase remains order-backed and payment-backed
- bundle purchase remains order-backed and payment-backed
- webhook remains payment-confirmation authority
- frontend never becomes authority
- Stripe never becomes authority
- membership remains separate
- bundles remain separate and course-entitlement-only

## Stop Conditions

- stop if any gate still allows implicit sellability
- stop if any gate allows Stripe or frontend authority
- stop if any gate permits course or bundle purchase to affect membership

## Out Of Scope

- non-monetization domain tests
- payouts
- Stripe Connect
