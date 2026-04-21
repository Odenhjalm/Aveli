# CFO-000 BASELINE FAMILY ORDER FOUNDATION

- TYPE: `OWNER`
- GROUP: `BASELINE`
- DEPENDS_ON: `[]`

## Problem Statement

The locked contract now requires course-family ordering to be contiguous,
zero-based, unique within `course_group_id`, and transition-safe for create,
move, reorder, and delete. Current Baseline V2 only enforces uniqueness plus
`group_position >= 0` on `app.courses`.

That means baseline truth is still missing the canonical substrate required to
enforce deterministic family transitions on clean replay.

## Contract References

- [SYSTEM_LAWS.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/SYSTEM_LAWS.md)
  - `1. Contract Authority Law`
  - `4. Cross-Domain Determinism Law`
  - `5. No-Fallback And Stop Law`
- [AVELI_COURSE_DOMAIN_SPEC.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md)
  - `3. CANONICAL FIELD DEFINITIONS`
  - `4. RELATION GRAPH`
  - `7. PROGRESSION MODEL`
  - `11. FORBIDDEN PATTERNS`
  - `13. MIGRATION BOUNDARY`
- [course_access_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_access_contract.md)
  - `4. PROTECTED COURSE-ACCESS LAW`
- [course_monetization_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_monetization_contract.md)
  - `6. COURSE BUNDLE DOMAIN`
- [commerce_membership_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/commerce_membership_contract.md)
  - `7. COURSE BUNDLES DOMAIN`

## Audit Inputs

- `CFA-01`
- `CFA-02`
- `CFA-03`

## Target Files

- `backend/supabase/baseline_v2_slots/V2_0023_course_family_ordering.sql`
- `backend/supabase/baseline_v2_slots.lock.json`

## Expected Outcome

- clean Baseline V2 replay gains append-only enforcement substrate for:
  - contiguous `0..(n-1)` ordering per `course_group_id`
  - exactly one position `0` per family
  - create into new family only at `0`
  - same-family reorder with sibling shifting
  - cross-family move with source collapse and target shift
  - delete collapse of remaining family positions
- enforcement remains rooted only in `app.courses`
- no bundle table or bundle snapshot becomes course-family authority

## Verification Requirement

- replay from scratch proves the new slot applies cleanly
- replay demonstrates invalid sparse and duplicate family states fail closed
- replay demonstrates valid create, move, reorder, and delete transitions commit
  transactionally
- replay proves no access or commerce table is required to validate family order

## Go Condition

- append-only baseline enforcement can be expressed without changing canonical
  ownership
- the enforcement substrate can live entirely in Baseline V2 plus replay tests
- the implementation does not reinterpret bundles as family order

## Blocked Condition

- blocked if enforcement requires a second owner outside `app.courses`
- blocked if enforcement requires reusing `app.course_bundles`,
  `app.course_bundle_courses`, or `app.bundle_order_courses`
- blocked if enforcement cannot be made replayable from scratch

## Out Of Scope

- backend route behavior
- frontend authoring controls
- learner rendering changes

