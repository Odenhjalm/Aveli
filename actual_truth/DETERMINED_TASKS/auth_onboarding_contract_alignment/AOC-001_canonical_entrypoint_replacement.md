# AOC-001_CANONICAL_ENTRYPOINT_REPLACEMENT

- TYPE: `OWNER`
- TITLE: `Replace mounted Auth + Onboarding entrypoints with the canonical contract inventory`
- DOMAIN: `route authority`
- CLASSIFICATION: `REPLACE`

## Problem Statement

The canonical contract locks Auth + Onboarding entrypoints to `/auth/register`, `/auth/login`, `/auth/forgot-password`, `/auth/reset-password`, `/auth/refresh`, `/auth/send-verification`, `/auth/verify-email`, `/auth/validate-invite`, `/profiles/me`, and `/admin/teacher-requests/{user_id}/approve|reject`. The mounted runtime still omits `admin.router`, while frontend and validation surfaces still consume forbidden `/auth/me`, `/auth/request-password-reset`, and `/admin/teachers/*` paths.

## Primary Authority Reference

- `actual_truth/contracts/auth_onboarding_contract.md`
- `actual_truth/Aveli_System_Decisions.md:96`
- `actual_truth/Aveli_System_Decisions.md:413`

## Drift Evidence

- `backend/app/main.py:173` and `backend/app/main.py:175` mount `auth.router` and `profiles.router`, but no `admin.router` mount exists.
- `backend/app/routes/admin.py:53` and `backend/app/routes/admin.py:68` define forbidden `/admin/teachers/*` handlers beside canonical `/admin/teacher-requests/*`.
- `frontend/lib/api/api_paths.dart:4` and `frontend/lib/api/api_paths.dart:7` still point to `/auth/request-password-reset` and `/auth/me`.
- `frontend/lib/features/community/data/admin_repository.dart:22` and `frontend/lib/features/community/data/admin_repository.dart:30` still call `/admin/teachers/*`.
- `backend/tests/utils.py:27` and many backend tests still read `/auth/me`.

## Implementation Surfaces Affected

- `backend/app/main.py`
- `backend/app/routes/admin.py`
- `frontend/lib/api/api_paths.dart`
- `frontend/lib/api/auth_repository.dart`
- `frontend/lib/data/repositories/profile_repository.dart`
- `frontend/lib/features/community/data/admin_repository.dart`
- `backend/tests`
- `backend/scripts`

## DEPENDS_ON

- None

## Exact Implementation Steps

1. Mount `admin.router` in `backend/app/main.py`.
2. Remove `/admin/teachers/{user_id}/approve` and `/admin/teachers/{user_id}/reject` from `backend/app/routes/admin.py` so only `/admin/teacher-requests/*` remains canonical.
3. Replace every Auth + Onboarding current-user consumer of `/auth/me` with `/profiles/me`.
4. Replace every Auth + Onboarding password-reset initiation consumer of `/auth/request-password-reset` with `/auth/forgot-password`.
5. Replace every teacher-approval caller of `/admin/teachers/*` with `/admin/teacher-requests/*`.
6. Add a contract grep gate that fails on `/auth/me`, `/auth/request-password-reset`, and `/admin/teachers/` inside Auth + Onboarding runtime, frontend, test, and script scope.

## Acceptance Criteria

- Mounted runtime exposes the canonical teacher-request approval endpoints.
- No mounted or consumed Auth + Onboarding surface uses `/auth/me`.
- No mounted or consumed Auth + Onboarding surface uses `/auth/request-password-reset`.
- No mounted or consumed Auth + Onboarding surface uses `/admin/teachers/*`.
- No fallback route remains for current-user, password-reset initiation, or teacher approval.

## Stop Conditions

- Stop if another mounted router defines a second current-user or teacher-approval path outside the audited files.
- Stop if a downstream caller still depends on legacy endpoints after canonical replacements are available.

## Out Of Scope

- Avatar upload routes
- Membership or checkout flows that do not act as Auth + Onboarding authority

