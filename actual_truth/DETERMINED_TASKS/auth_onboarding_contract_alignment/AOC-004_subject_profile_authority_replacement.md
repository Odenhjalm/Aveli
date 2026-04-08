# AOC-004_SUBJECT_PROFILE_AUTHORITY_REPLACEMENT

- TYPE: `OWNER`
- TITLE: `Replace profile-authority leakage with canonical auth-subject authority only`
- DOMAIN: `data authority`
- CLASSIFICATION: `REPLACE`

## Problem Statement

The current contract layer routes onboarding and role field authority through `onboarding_teacher_rights_contract.md`, while `auth_onboarding_contract.md` only defines route and execution boundaries for those fields. `app.auth_subjects` is the only owner for `onboarding_state`, `role_v2`, `role`, and `is_admin`, while `app.profiles` is projection-only. The repo still contains write paths that persist auth-subject fields through `app.profiles`, and the register request surface still accepts forbidden `referral_code`.

## Primary Authority Reference

- `actual_truth/contracts/auth_onboarding_contract.md:50-57`
- `actual_truth/contracts/auth_onboarding_contract.md:156-160`
- `actual_truth/contracts/onboarding_teacher_rights_contract.md:101-123`
- `actual_truth/contracts/SYSTEM_LAWS.md:72-74`

## Drift Evidence

- `backend/app/repositories/auth.py:71-114` still conditionally writes `onboarding_state`, `role_v2`, `role`, and `is_admin` into `app.profiles`.
- `backend/app/repositories/auth.py:168` and `backend/app/repositories/auth.py:214-277` still keep `referral_code` in the register persistence path.
- `backend/app/repositories/auth.py:293-300` still persists auth-subject fields through `_upsert_profile_row`.
- `backend/app/repositories/profiles.py:47` and `backend/app/repositories/profiles.py:64-65` still expose profile-driven onboarding mutation.
- `backend/app/schemas/__init__.py:73` still accepts `referral_code` on `AuthRegisterRequest`.
- `frontend/lib/api/auth_repository.dart:59` still sends `referral_code`.

## Implementation Surfaces Affected

- `backend/app/repositories/auth.py`
- `backend/app/repositories/profiles.py`
- `backend/app/routes/auth.py`
- `backend/app/schemas/__init__.py`
- `frontend/lib/api/auth_repository.dart`
- `backend/tests`
- `backend/scripts`

## DEPENDS_ON

- `AOC-002`

## Exact Implementation Steps

1. Remove `referral_code` from the Auth + Onboarding register request schema and from frontend Auth + Onboarding payload builders.
2. Strip `_upsert_profile_row` of any onboarding or role writes so it persists profile projection fields only.
3. Remove `onboarding_state` as a writable parameter from `backend/app/repositories/profiles.py.update_profile`.
4. Keep canonical subject creation and mutation only in `app.auth_subjects`.
5. Rewrite tests, fixtures, and scripts that mutate `app.profiles.role_v2` or `app.profiles.is_admin` so they use `app.auth_subjects` or canonical admin approval instead.

## Acceptance Criteria

- No Auth + Onboarding write path persists onboarding or role authority through `app.profiles`.
- Register request rejects `referral_code`.
- Profile update surfaces cannot mutate onboarding or role authority.
- No repository write path invents alternate field authority or fallback write behavior.

## Stop Conditions

- Stop if a referral or membership flow still depends on Auth + Onboarding register accepting `referral_code`; that dependency must be isolated into its own contract scope.
- Stop if any hidden repository helper reintroduces auth-subject fields into `app.profiles`.

## Out Of Scope

- Membership plan semantics
- Stripe behavior
- Course-access logic
