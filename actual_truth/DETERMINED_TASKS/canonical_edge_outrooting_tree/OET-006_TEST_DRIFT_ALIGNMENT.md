# OET-006 TEST DRIFT ALIGNMENT

- TYPE: `GATE`
- GROUP: `TEST ALIGNMENT`
- REQUIRED BEFORE FUTURE CORE FEATURE WORK: `YES`
- EXECUTION CLASS: `REQUIRED VERIFICATION`

## Problem Statement

Multiple backend tests still model unmounted routes, stale drift surfaces, or outdated ownership and claim assumptions.
At the same time, guard tests already exist for several canonical boundaries and should be preserved.

## Contract References

- [auth_onboarding_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/auth_onboarding_contract.md)
- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)
- [course_access_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_access_contract.md)

## Audit Inputs

- `OEA-02`
- `OEA-03`
- `OEA-04`
- `OEA-05`
- `OEA-07`

## Implementation Surfaces Affected

- `backend/tests/test_api_smoke.py`
- `backend/tests/test_feed_permissions.py`
- `backend/tests/test_community_flows.py`
- `backend/tests/test_landing_popular_courses_filters_demo.py`
- `backend/tests/test_studio_sessions_smoke.py`
- `backend/tests/test_sfu_api.py`
- `backend/tests/test_media_api.py`
- `backend/tests/test_upload_legacy_routes.py`
- `backend/tests/test_commerce_contract_gate.py`
- `backend/tests/test_auth_subject_authority_gate.py`
- `backend/tests/test_events_notifications.py`

## Depends On

- `OET-001`
- `OET-002`
- `OET-003`
- `OET-004`

## Acceptance Criteria

- scoped tests assert only mounted runtime truth and protected canonical core boundaries
- stale tests that still target unmounted route trees or legacy authority assumptions are removed, rewritten, or explicitly quarantined
- guard tests for upload legacy-route retirement, commerce route boundaries, auth-subject authority, and notification audience separation remain intact or are strengthened
- no test in scope reintroduces `created_by`, token-payload authority, or unmounted route inventory as canonical truth

## Stop Conditions

- stop if tests still pass while contradicting mounted runtime truth
- stop if scoped tests keep asserting removed or unmounted route surfaces as canonical
- stop if tests become the first place where a new authority decision is invented

## Out Of Scope

- runtime implementation beyond the audited cleanup perimeter
- baseline or schema changes
- optional later hardening domains not required for current gate closure
