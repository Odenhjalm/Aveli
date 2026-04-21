# SOI-002 DOMAIN VALIDATION AND STATE HASH ENFORCEMENT

- TASK_ID: `SOI-002`
- TYPE: `OWNER`
- GROUP: `BACKEND DOMAIN IMPLEMENTATION`

## Purpose

Implement the backend-owned validation and deterministic state model for
special-offer state so create and update actions cannot persist invalid course
sets or stale freshness semantics.

## Contract References

- `actual_truth/contracts/special_offer_domain_contract.md`
- `actual_truth/contracts/special_offer_execution_contract.md`
- `actual_truth/contracts/SYSTEM_LAWS.md`
- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`

## DEPENDS_ON

- `SOI-001`

## Dependency Requirements

- enforce selected-course count `1..5`
- reject duplicate selected courses
- enforce same-teacher course set in MVP
- treat price as special-offer domain truth
- keep `state_hash` as the only canonical current versus stale comparison
  surface

## Exact Scope

- validation logic for create and update
- backend-owned canonical ordering normalization for selected courses
- state-hash recomputation verification against teacher, ordered courses, and
  price
- image-required and image-current semantics derived from state hash comparison,
  not boolean flags

## Verification Criteria

- zero-course and more-than-five-course payloads fail closed
- duplicate course selection fails closed
- cross-teacher course sets fail closed in MVP
- price is validated before persistence
- current versus stale status derives only from
  `special_offers.state_hash == special_offer_composite_image_outputs.state_hash`

## GO Condition

Go when backend validation makes invalid special-offer state unpersistable and
freshness semantics are purely hash-based and deterministic.

## BLOCKED Condition

Stop if any implementation introduces hidden randomness, boolean freshness
flags, image-derived pricing, or frontend-owned validation truth.

## Out Of Scope

- image byte composition
- media asset creation
- frontend confirmation UX
