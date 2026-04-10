# CMTZ-008 PURCHASE INTEGRATION

- TYPE: `OWNER`
- GROUP: `PURCHASE INTEGRATION`

## Problem Statement

Verified repository state already has contract-ratified order-backed course checkout and substantially correct order-backed bundle checkout, but purchase substrate baseline ownership lives outside this tree, course mapping is incomplete, and student-facing bundle purchase initiation is not fully verified end-to-end.

This task aligns course and bundle purchase integration to contract truth while preserving order/payment/webhook authority.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
  - `1. CONTRACT LAW`
  - `2. COURSE MONETIZATION AUTHORITY`
  - `6. COURSE BUNDLE DOMAIN`
  - `8. PURCHASE FLOW`
  - `9. MEMBERSHIP SEPARATION`
- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)
  - order/payment authority and webhook law

## Audit Inputs

- `CMA-02`
- `CMA-03`
- `CMA-07`
- `CMA-09`
- `CMA-10`
- `CMA-16`

## Implementation Surfaces Affected

- `backend/app/routes/api_checkout.py`
- `backend/app/routes/course_bundles.py`
- `backend/app/services/checkout_service.py`
- `backend/app/services/course_bundles_service.py`
- `backend/app/routes/stripe_webhooks.py`

## Depends On

- `CMT-000_PURCHASE_SUBSTRATE_BASELINE_FOUNDATION` from `commerce_membership_contract_alignment`
- `CMTZ-003`
- `CMTZ-006`
- `CMTZ-007`

## Acceptance Criteria

- course purchase remains order-backed and payment-backed
- bundle purchase remains order-backed and payment-backed
- purchase gating consumes canonical sellability
- webhook remains the only canonical payment-confirmation path
- bundle purchase grants only course enrollments
- course and bundle purchase never mutate membership
- any student-facing bundle purchase entrypoint resolves to canonical backend checkout surfaces

## Stop Conditions

- stop if webhook authority is bypassed
- stop if bundle or course purchase begins to affect membership
- stop if payment-link projection becomes authority by itself

## Out Of Scope

- teacher authoring UI
- payout logic
- marketplace settlement
