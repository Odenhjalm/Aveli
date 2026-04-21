# CFO-003 STUDIO API FAMILY POSITION ALIGNMENT

- TYPE: `OWNER`
- GROUP: `STUDIO API`
- DEPENDS_ON:
  - `CFO-002`

## Problem Statement

Studio payload shapes already expose `course_group_id` and `group_position`, but
current route semantics do not yet enforce the locked transition rules at the
HTTP boundary.

The canonical transport surfaces must preserve the existing single-owner route
set while rejecting ambiguous or partial family-move intent.

## Contract References

- [SYSTEM_LAWS.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/SYSTEM_LAWS.md)
  - `1. Contract Authority Law`
  - `5. No-Fallback And Stop Law`
  - `7. Execution-Boundary Law`
- [AVELI_COURSE_DOMAIN_SPEC.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md)
  - `3. CANONICAL FIELD DEFINITIONS`
  - `7. PROGRESSION MODEL`
  - `11. FORBIDDEN PATTERNS`
- [course_lesson_editor_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_lesson_editor_contract.md)
  - `4. CANONICAL ENTRYPOINTS`
  - `5. STRUCTURE WRITE CONTRACTS`
  - `7. STRUCTURE READ CONTRACT`

## Audit Inputs

- `CFA-04`
- `CFA-05`
- `CFA-06`
- `CFA-10`

## Target Files

- `backend/app/schemas/__init__.py`
- `backend/app/routes/studio.py`
- `backend/tests/test_courses_studio.py`
- `backend/tests/test_api_smoke.py`

## Expected Outcome

- `POST /studio/courses` remains the canonical create surface and rejects
  contract-invalid new-family creates
- `PATCH /studio/courses/{course_id}` remains the canonical move/reorder surface
  and enforces explicit target semantics
- no new `step` alias is accepted or emitted
- no second course-family endpoint is introduced unless the editor contract is
  explicitly changed first
- API errors are deterministic for ambiguous family/order writes

## Verification Requirement

- studio API tests prove:
  - new-family create requires `group_position = 0`
  - same-family reorder succeeds with explicit target position
  - cross-family move requires explicit target `course_group_id` and
    `group_position`
  - delete collapses remaining sibling positions
- API tests preserve read payload field names already ratified by contract

## Go Condition

- `CFO-002` lands with canonical backend transition logic
- route alignment can preserve the existing editor contract surface set

## Blocked Condition

- blocked if route design requires a second transport owner for family order
- blocked if update semantics remain ambiguous when `course_group_id` changes
  without explicit `group_position`
- blocked if API repair would reintroduce legacy `step`

## Out Of Scope

- studio widget controls
- learner/public render changes

