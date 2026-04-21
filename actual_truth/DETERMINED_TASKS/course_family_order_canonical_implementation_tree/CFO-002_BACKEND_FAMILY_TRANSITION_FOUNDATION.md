# CFO-002 BACKEND FAMILY TRANSITION FOUNDATION

- TYPE: `OWNER`
- GROUP: `BACKEND SERVICE/REPOSITORY`
- DEPENDS_ON:
  - `CFO-001`

## Problem Statement

Current backend create, update, and delete flows pass `course_group_id` and
`group_position` straight through to single-row SQL writes.
They do not implement the locked transition semantics for create-into-existing
family, cross-family move, same-family reorder, or delete-collapse.

## Contract References

- [SYSTEM_LAWS.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/SYSTEM_LAWS.md)
  - `4. Cross-Domain Determinism Law`
  - `5. No-Fallback And Stop Law`
- [AVELI_COURSE_DOMAIN_SPEC.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md)
  - `7. PROGRESSION MODEL`
  - `11. FORBIDDEN PATTERNS`
  - `12. FAILURE MODEL`
- [course_access_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_access_contract.md)
  - `4. PROTECTED COURSE-ACCESS LAW`

## Audit Inputs

- `CFA-04`
- `CFA-05`
- `CFA-06`

## Target Files

- `backend/app/repositories/courses.py`
- `backend/app/services/courses_service.py`
- `backend/app/types/course_row.py`
- `backend/tests/test_course_family_transition_service.py`

## Expected Outcome

- course create uses canonical family-order logic rather than raw row insertion
- course update distinguishes:
  - reorder within same family
  - move between families
  - no-op structural patch
- changing `course_group_id` requires explicit target `group_position`
- delete collapses remaining sibling positions after row removal
- transition semantics live in backend transaction logic and baseline substrate,
  not in frontend code
- access logic remains owned by `required_enrollment_source` and
  `course_enrollments`

## Verification Requirement

- integration tests cover create, move, reorder, and delete through service and
  repository layers
- tests prove source-family collapse and target-family shift happen in one
  transaction
- tests prove backend does not derive access from `group_position`

## Go Condition

- `CFO-001` proves replay-backed baseline enforcement is available
- repository and service layers can depend on canonical baseline truth instead
  of hand-rolled fallback behavior

## Blocked Condition

- blocked if backend continues to rely on blind single-row updates
- blocked if transition semantics are split between route handlers and frontend
- blocked if `group_position` starts affecting access or monetization logic

## Out Of Scope

- frontend mutation controls
- learner-facing rendering

