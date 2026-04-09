# CMTZ-005 BUNDLE PRICING AUTHORITY

- TYPE: `OWNER`
- GROUP: `BUNDLE PRICING`

## Problem Statement

Verified repository state shows that bundle price exists and is persisted, but bundle readiness is partially inferred through `is_active` and other ad hoc prerequisites rather than a contract-grade backend pricing authority model.

This task aligns teacher bundle pricing to backend-owned canonical truth.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
  - `3. PRICING AUTHORITY`
  - `6. COURSE BUNDLE DOMAIN`
  - `7. TEACHER SELLING EXPERIENCE LAW`
  - `11. FAILURE MODEL`
  - `12. FORBIDDEN PATTERNS`

## Audit Inputs

- `CMA-08`

## Implementation Surfaces Affected

- `backend/app/routes/course_bundles.py`
- `backend/app/services/course_bundles_service.py`
- `backend/app/repositories/course_bundles.py`
- `frontend/lib/features/teacher/*`

## Depends On

- `CMTZ-001`
- `CMTZ-004`

## Acceptance Criteria

- teacher bundle pricing is intent only until backend validation and persistence succeed
- bundle price is independent from the sum of included course prices
- backend validates ownership, composition, and pricing input
- `is_active` no longer acts as a hidden sellability proxy
- frontend bundle builder remains non-authoritative

## Stop Conditions

- stop if frontend bundle UI becomes price authority
- stop if arithmetic on component course prices becomes implicit bundle truth
- stop if bundle price mutates historical purchase truth

## Out Of Scope

- bundle Stripe product creation
- explicit sellability computation
- checkout flow
