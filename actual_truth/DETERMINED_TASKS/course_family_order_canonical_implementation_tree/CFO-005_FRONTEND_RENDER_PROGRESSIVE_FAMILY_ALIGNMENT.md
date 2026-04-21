# CFO-005 FRONTEND RENDER PROGRESSIVE FAMILY ALIGNMENT

- TYPE: `OWNER`
- GROUP: `FRONTEND RENDER`
- DEPENDS_ON:
  - `CFO-003`

## Problem Statement

Learner-facing course rendering still canonizes fixed three-step semantics.

Current journey layout:

- skips `group_position = 0`
- hardcodes `step1`, `step2`, and `step3`
- silently keeps the first duplicate position instead of treating duplicate
  family order as invalid backend state

That rendering model is narrower than the locked contract and cannot represent a
general contiguous family sequence.

## Contract References

- [AVELI_COURSE_DOMAIN_SPEC.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md)
  - `3. CANONICAL FIELD DEFINITIONS`
  - `7. PROGRESSION MODEL`
  - `11. FORBIDDEN PATTERNS`
  - `12. FAILURE MODEL`
- [course_public_surface_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_public_surface_contract.md)
  - learner structure read rules
- [learner_public_edge_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/learner_public_edge_contract.md)
  - response-shape rules for `course_group_id` and `group_position`

## Audit Inputs

- `CFA-09`

## Target Files

- `frontend/lib/features/courses/presentation/course_journey_layout.dart`
- `frontend/lib/features/courses/presentation/course_catalog_page.dart`
- `frontend/test/unit/course_journey_layout_test.dart`
- `frontend/test/widgets/course_catalog_journey_layout_test.dart`
- `frontend/test/widgets/courses_showcase_section_order_test.dart`

## Expected Outcome

- learner rendering consumes general family order from backend-authored
  `course_group_id` plus `group_position`
- no fixed `step1/step2/step3` structure remains as semantic authority
- position `0` is handled as the structural intro slot only
- duplicate or sparse family states are not normalized into alternate frontend
  truth

## Verification Requirement

- unit and widget tests are rewritten around general family ordering instead of
  three fixed step slots
- tests stop codifying "keep first duplicate" behavior
- tests preserve the existing rule that legacy `step` is forbidden

## Go Condition

- `CFO-003` preserves canonical read payloads
- learner/public surfaces continue to emit `course_group_id` and
  `group_position`

## Blocked Condition

- blocked if rendering still depends on a fixed `step1/step2/step3` contract
- blocked if frontend would need to synthesize missing family positions
- blocked if duplicate backend positions are silently canonized in UI

## Out Of Scope

- studio course editing controls
- backend transition orchestration

