# AOC-007_AUTH_ONBOARDING_GATE_REWRITE

- TYPE: `GATE`
- TITLE: `Rewrite validation gates, fixtures, and scripts to canonical Auth + Onboarding truth only`
- DOMAIN: `validation authority`
- CLASSIFICATION: `REMOVE`

## Problem Statement

Validation surfaces still assert forbidden endpoints, forbidden states, forbidden fields, and forbidden route modules. Until validation is rewritten, legacy Auth + Onboarding authority can re-enter the system even if runtime code is corrected.

## Primary Authority Reference

- `actual_truth/contracts/auth_onboarding_contract.md:27-40`
- `actual_truth/contracts/auth_onboarding_contract.md:130-136`
- `actual_truth/contracts/auth_onboarding_contract.md:156-160`
- `actual_truth/contracts/onboarding_teacher_rights_contract.md:193-199`
- `actual_truth/contracts/SYSTEM_LAWS.md:72-74`
- `actual_truth/Aveli_System_Decisions.md:413`

## Implementation Surfaces Affected

- `backend/tests`
- `backend/test_email_verification.py`
- `frontend/test`
- `backend/scripts`

## DEPENDS_ON

- `AOC-001`
- `AOC-003`
- `AOC-004`
- `AOC-005`
- `AOC-006`

## Exact Implementation Steps

1. Rewrite backend tests and helpers to use `/profiles/me`, `/auth/forgot-password`, and `/admin/teacher-requests/*` only.
2. Rewrite backend tests, seeds, and fixtures to use `app.auth_subjects` or canonical admin approval for onboarding and role mutations, and to validate effective-role reads as `role_v2` first and `role` only as compatibility fallback.
3. Rewrite frontend tests to use `incomplete` and `completed` only and to stop asserting `is_teacher`, `membership_active`, `email_verified`, `user`, or `professional`.
4. Add repository-wide grep gates for forbidden Auth + Onboarding patterns:
   - `/auth/me`
   - `/auth/request-password-reset`
   - `/admin/teachers/`
   - `registered_unverified`
   - `verified_unpaid`
   - `access_active_profile_incomplete`
   - `access_active_profile_complete`
   - `welcomed`
   - `membership_active`
   - `is_teacher`
   - `referral_code`
   - direct imports of `api_auth` or `api_profiles`
5. Re-record `/profiles/me` mocks and fixtures to the canonical current-profile response shape:
   - `user_id`
   - `email`
   - `display_name`
   - `bio`
   - `photo_url`
   - `avatar_media_id`
   - `created_at`
   - `updated_at`
   - and fail if `/profiles/me` fixtures include `onboarding_state`, `role_v2`, or `is_admin`

## Acceptance Criteria

- Validation surfaces no longer encode legacy Auth + Onboarding authority or outdated `/profiles/me` response assumptions.
- No grep gate forbidden pattern remains in Auth + Onboarding runtime, test, or script scope.
- Fixtures and mocks match the canonical `/profiles/me` contract response shape exactly.

## Stop Conditions

- Stop if another domain still depends on forbidden patterns for a non-auth contract; that dependency must be split from this scope first.
- Stop if a required validation scenario has no canonical runtime surface yet.

## Out Of Scope

- Full-system verification outside Auth + Onboarding scope
