# OET-003 EVENTS OWNERSHIP CLEANUP

- TYPE: `OWNER`
- GROUP: `ACTIVE AUXILIARY DRIFT`
- REQUIRED BEFORE FUTURE CORE FEATURE WORK: `YES`
- EXECUTION CLASS: `BLOCKER`
- CURRENT STATUS: `HISTORICAL / VERIFIED COMPLETE`

## Historical Note

The problem statement below records the pre-execution audit state and is retained only as historical task context.

## Problem Statement

Mounted `backend/app/routes/api_events.py` already consumes canonical membership access, but owner-only branches and visibility logic still compare against `created_by`.

That leaves a mounted runtime-adjacent ownership shortcut alive inside the events domain.

## Contract References

- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)
- [auth_onboarding_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/auth_onboarding_contract.md)
- [supabase_integration_boundary_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/supabase_integration_boundary_contract.md)

## Audit Inputs

- `OEA-01`
- `OEA-04`

## Implementation Surfaces Affected

- `backend/app/routes/api_events.py`
- `backend/app/schemas/events.py`
- `backend/tests/test_events_notifications.py`

## Depends On

- `CMT-001_BASELINE_MEMBERSHIP_FOUNDATION`
- `AOI-003_baseline_bound_auth_persistence`

## Acceptance Criteria

- mounted events runtime no longer treats `created_by` as a legacy standalone authority shortcut for owner-only branches
- canonical app-membership access continues to be consumed only from `app.memberships`
- event-participant and membership semantics remain separate
- any surviving owner authority in scope is explicit, singular, and already evidenced by current runtime truth before implementation proceeds
- no task in scope invents a new cross-domain authority model for events

## Stop Conditions

- stop if the task requires a new event authority decision that is not already evidenced in scoped runtime truth
- stop if the task attempts to redefine membership, auth-subject, order, payment, or course-enrollment core
- stop if `created_by` remains the effective mounted owner-only shortcut when the task is complete

## Out Of Scope

- course ownership substrate
- JWT issuance cleanup
- AI or seminar dead-code quarantine
- contract expansion for a new events domain model
