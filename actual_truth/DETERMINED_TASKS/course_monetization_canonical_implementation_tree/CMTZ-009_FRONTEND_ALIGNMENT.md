# CMTZ-009 FRONTEND ALIGNMENT

- TYPE: `OWNER`
- GROUP: `FRONTEND ALIGNMENT`

## Problem Statement

Verified repository state shows that frontend course checkout is already backend-authoritative, but teacher selling UX remains partially incomplete and no verified student-facing bundle purchase initiation path was found.

This task aligns teacher and student monetization UI to backend-owned projections only.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
  - `3. PRICING AUTHORITY`
  - `4. SELLABLE MODEL`
  - `7. TEACHER SELLING EXPERIENCE LAW`
  - `8. PURCHASE FLOW`
  - `12. FORBIDDEN PATTERNS`
- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)
  - frontend non-authority law

## Audit Inputs

- `CMA-09`
- `CMA-10`
- `CMA-11`
- `CMA-15`
- `CMA-16`

## Implementation Surfaces Affected

- `frontend/lib/features/studio/*`
- `frontend/lib/features/teacher/*`
- `frontend/lib/features/paywall/*`
- `frontend/lib/core/deeplinks/*`
- `frontend/landing/*`

## Depends On

- `CMTZ-002`
- `CMTZ-005`
- `CMTZ-007`
- `CMTZ-008`

## Acceptance Criteria

- teacher pricing UI remains intent-only and projection-only
- teacher bundle UI remains intent-only and projection-only
- frontend student purchase paths use canonical backend-owned checkout surfaces
- bundle selling flow has a verified frontend path if it is exposed in MVP
- frontend does not infer sellability from local UI state
- frontend does not infer authority from Stripe runtime state
- frontend never mutates course, bundle, or membership authority directly

## Stop Conditions

- stop if teacher home or course editor becomes authority
- stop if payment-link copy UX remains the only effective bundle selling path without canonical validation
- stop if Stripe runtime or local form state affects authority decisions

## Out Of Scope

- backend Stripe mapping implementation
- schema work
- webhook logic
