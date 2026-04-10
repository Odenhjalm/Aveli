# OET-005 UNMOUNTED ENROLLMENTS QUARANTINE

- TYPE: `OWNER`
- GROUP: `INACTIVE / DEAD-CODE QUARANTINE`
- REQUIRED BEFORE FUTURE CORE FEATURE WORK: `NO`
- EXECUTION CLASS: `OPTIONAL LATER HARDENING`

## Problem Statement

Inactive AI and seminar edges still read `app.enrollments` from `backend/app/services/tool_dispatcher.py` and `backend/app/repositories/seminars.py`.

Those paths are currently unmounted, but they remain a dangerous reactivation perimeter around canonical `app.course_enrollments`.

## Contract References

- [course_access_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_access_contract.md)
- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)

## Audit Inputs

- `OEA-06`

## Implementation Surfaces Affected

- `backend/app/services/tool_dispatcher.py`
- `backend/app/repositories/seminars.py`
- `backend/app/routes/api_ai.py`
- `backend/app/routes/seminars.py`
- `backend/app/routes/api_sfu.py`
- `backend/tests/test_seminar_rpcs.py`
- `backend/tests/test_seminar_sessions.py`
- `backend/tests/test_sfu_api.py`

## Depends On

- `OET-011`

## Acceptance Criteria

- no inactive surface in scope reads `app.enrollments`
- any surviving AI or seminar access logic in scope consumes canonical `app.course_enrollments` only, or remains explicitly quarantined and unmounted
- route inventory in scope makes the quarantine boundary explicit
- no scoped change reactivates dormant AI, seminar, or SFU behavior as a side effect

## Stop Conditions

- stop if the task would reactivate dormant endpoints before canonical access logic exists in scope
- stop if the task touches mounted course-access core or redefines membership authority
- stop if `app.enrollments` remains reachable through any scoped dormant route after completion

## Out Of Scope

- mounted studio or events cleanup
- JWT shadow claims
- support-surface introspection hardening
- contract or baseline changes
