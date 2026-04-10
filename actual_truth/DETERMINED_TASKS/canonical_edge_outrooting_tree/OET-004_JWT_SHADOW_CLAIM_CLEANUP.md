# OET-004 JWT SHADOW CLAIM CLEANUP

- TYPE: `OWNER`
- GROUP: `SHADOW AUTHORITY CLEANUP`
- REQUIRED BEFORE FUTURE CORE FEATURE WORK: `YES`
- EXECUTION CLASS: `AUXILIARY`

## Problem Statement

`backend/app/routes/auth.py` still emits `role` and `is_admin` into token claims even though backend current-user authority is already read canonically from `app.auth_subjects` in `backend/app/auth.py`.

This leaves a live shadow-authority surface around the stable auth core.

## Contract References

- [auth_onboarding_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/auth_onboarding_contract.md)
- [profile_projection_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/profile_projection_contract.md)

## Audit Inputs

- `OEA-01`
- `OEA-05`

## Implementation Surfaces Affected

- `backend/app/routes/auth.py`
- `backend/app/auth.py`
- `backend/tests/test_auth_subject_authority_gate.py`

## Depends On

- `AOI-003_baseline_bound_auth_persistence`

## Acceptance Criteria

- token issuance no longer leaves `role` or `is_admin` as a second effective authority input beside `app.auth_subjects`
- backend current-user authority remains owned only by canonical `app.auth_subjects` reads
- any surviving compatibility claim in scope is explicitly non-authoritative and cannot bypass canonical subject reads
- no task in scope changes canonical role, admin, onboarding-state, or profile-projection ownership

## Stop Conditions

- stop if token payload continues to function as a live authority shortcut
- stop if the task attempts to redefine `app.auth_subjects` ownership or mutate auth core decisions
- stop if backend tests can still pass while payload claims contradict canonical subject truth

## Out Of Scope

- onboarding contract redesign
- admin grant or revoke behavior redesign
- frontend feature expansion not evidenced by the audit
- membership or commerce core
