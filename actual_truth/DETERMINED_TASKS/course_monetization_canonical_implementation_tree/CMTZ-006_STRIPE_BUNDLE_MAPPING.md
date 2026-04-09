# CMTZ-006 STRIPE BUNDLE MAPPING

- TYPE: `OWNER`
- GROUP: `STRIPE BUNDLE MAPPING`

## Problem Statement

Verified repository state shows that bundle Stripe mapping already exists and is functional, but it is currently intertwined with readiness assumptions rather than an explicit contract-aligned monetization model.

This task preserves the correct backend-owned bundle mapping flow while aligning it to the contract.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
  - `5. STRIPE PRODUCT MODEL`
  - `6. COURSE BUNDLE DOMAIN`
  - `8. PURCHASE FLOW`
  - `12. FORBIDDEN PATTERNS`

## Audit Inputs

- `CMA-07`
- `CMA-08`

## Implementation Surfaces Affected

- `backend/app/services/course_bundles_service.py`
- `backend/app/repositories/course_bundles.py`
- baseline-backed monetization substrate from `CMTZ-001`

## Depends On

- `CMTZ-001`
- `CMTZ-004`
- `CMTZ-005`

## Acceptance Criteria

- each sellable bundle maps to one backend-owned Stripe product and one active Stripe price at a time
- bundle Stripe mapping remains separate from course Stripe mapping
- new price changes create new Stripe prices for future bundle purchases only
- historical bundle purchases remain tied to original order/payment truth
- Stripe remains infrastructure only and never becomes authority

## Stop Conditions

- stop if bundle Stripe state becomes sellability authority
- stop if course Stripe mapping is reused as bundle product identity
- stop if frontend becomes part of bundle mapping authority

## Out Of Scope

- student frontend bundle purchase flow
- membership logic
- public discovery surfaces
