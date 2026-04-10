# OET-002 STUDIO QUIZ OWNERSHIP CLEANUP

- TYPE: `OWNER`
- GROUP: `ACTIVE AUTHORITY DRIFT`
- REQUIRED BEFORE FUTURE CORE FEATURE WORK: `YES`
- EXECUTION CLASS: `BLOCKER`

## Problem Statement

Mounted studio quiz routes still rely on `backend/app/models.py` helper logic that joins quizzes to courses and checks `c.created_by` inside `quiz_belongs_to_user`.

This keeps a second live course-ownership path inside mounted runtime even though canonical course ownership has already been ratified elsewhere.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
- [supabase_integration_boundary_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/supabase_integration_boundary_contract.md)

## Audit Inputs

- `OEA-01`
- `OEA-03`

## Implementation Surfaces Affected

- `backend/app/models.py`
- `backend/app/routes/studio.py`
- `backend/app/repositories/courses.py`

## Depends On

- `CMTZ-001_BASELINE_OWNERSHIP_AND_MONETIZATION_FOUNDATION`
- `AOI-003_baseline_bound_auth_persistence`

## Acceptance Criteria

- mounted studio quiz create, read, update, and delete flows no longer use `c.created_by` as ownership authority
- quiz ownership consumes only the preexisting canonical course ownership substrate
- mounted studio quiz behavior remains bounded to canonical ownership checks and does not add a second route-local authority model
- no mutation or reinterpretation of membership, purchase, auth-subject, or course-enrollment core occurs
- no new quiz-specific ownership field or fallback helper is introduced

## Stop Conditions

- stop if the task attempts to redefine course ownership or create a quiz-only authority model
- stop if the task touches checkout, webhook, membership, order, payment, or enrollment core
- stop if `created_by` remains in the mounted quiz ownership path after completion

## Out Of Scope

- home-audio ownership cleanup
- events authority
- JWT claim cleanup
- contract or baseline changes
