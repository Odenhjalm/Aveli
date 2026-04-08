# AOC-008_AUTH_ONBOARDING_AGGREGATE_GATE

- TYPE: `AGGREGATE`
- TITLE: `Aggregate verification for canonical Auth + Onboarding authority`
- DOMAIN: `aggregate verification`

## Problem Statement

Auth + Onboarding is aligned only when no legacy authority remains and the route inventory, schema inventory, repository writes, frontend consumers, and validation gates all point to the same contract truth.

## Primary Authority Reference

- `actual_truth/contracts/auth_onboarding_contract.md:27-40`
- `actual_truth/contracts/auth_onboarding_contract.md:130-136`
- `actual_truth/contracts/auth_onboarding_contract.md:156-160`
- `actual_truth/contracts/onboarding_teacher_rights_contract.md:101-123`
- `actual_truth/contracts/onboarding_teacher_rights_contract.md:193-199`
- `actual_truth/contracts/SYSTEM_LAWS.md:72-74`
- `actual_truth/Aveli_System_Decisions.md:96`
- `actual_truth/Aveli_System_Decisions.md:413`

## Implementation Surfaces Affected

- `actual_truth/DETERMINED_TASKS/auth_onboarding_contract_alignment/task_manifest.json`
- `backend/app/main.py`
- `backend/app/routes/auth.py`
- `backend/app/routes/profiles.py`
- `backend/app/routes/email_verification.py`
- `backend/app/routes/admin.py`
- `backend/app/repositories/auth.py`
- `backend/app/repositories/profiles.py`
- `backend/app/models.py`
- `frontend/lib`
- `backend/tests`
- `frontend/test`
- `backend/scripts`

## DEPENDS_ON

- `AOC-007`

## Exact Implementation Steps

1. Re-run contract-scoped grep for forbidden endpoints, forbidden fields, forbidden states, and forbidden imports.
2. Verify mounted route inventory exactly matches the canonical Auth + Onboarding inventory plus non-authoritative supporting profile-media paths.
3. Verify shared schema inventory exposes no extra Auth + Onboarding request or response fields, especially no onboarding, role, or admin fields on `GET /profiles/me`.
4. Verify repository write paths keep onboarding and role authority in `app.auth_subjects` only, and runtime role reads preserve canonical `role_v2 -> role` compatibility fallback behavior.
5. Emit a final PASS or FAIL artifact for the Auth + Onboarding contract cluster and stop.

## Acceptance Criteria

- No legacy Auth + Onboarding authority survives.
- Route inventory, schema inventory, repository writes, frontend consumers, and validation gates all align to the same contract truth.
- Any remaining `role` fallback matches canonical compatibility law, and no non-canonical fallback behavior survives.

## Stop Conditions

- Stop on any surviving forbidden pattern.
- Stop if more than one active Auth + Onboarding truth surface remains.

## Out Of Scope

- Execute-mode mutation
- Confirm-mode runtime verification
