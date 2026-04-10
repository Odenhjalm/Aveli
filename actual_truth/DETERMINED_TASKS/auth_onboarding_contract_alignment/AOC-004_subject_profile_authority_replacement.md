# AOC-004_SUBJECT_PROFILE_AUTHORITY_REPLACEMENT

- TYPE: `OWNER`
- TITLE: `Replace profile-authority leakage with canonical auth-subject authority only`
- DOMAIN: `data authority`
- CLASSIFICATION: `REPLACE`

## Problem Statement

The current contract layer routes onboarding and role field authority through `onboarding_teacher_rights_contract.md`, while `auth_onboarding_contract.md` only defines route and execution boundaries for those fields. `app.auth_subjects` is the only owner for `onboarding_state`, `role_v2`, `role`, and `is_admin`, while `app.profiles` is projection-only. Referral-driven membership grant is now canonically owned by `referral_membership_grant_contract.md`, while resulting membership state remains owned by `commerce_membership_contract.md`. The remaining active drift in this task is profile-authority leakage through `app.profiles`; auth-side referral coupling is already removed and should remain outside this task's active drift scope.

## Primary Authority Reference

- `actual_truth/contracts/auth_onboarding_contract.md:50-57`
- `actual_truth/contracts/auth_onboarding_contract.md:156-160`
- `actual_truth/contracts/referral_membership_grant_contract.md:11-18`
- `actual_truth/contracts/referral_membership_grant_contract.md:71-94`
- `actual_truth/contracts/commerce_membership_contract.md:21-25`
- `actual_truth/contracts/commerce_membership_contract.md:86-98`
- `actual_truth/contracts/onboarding_teacher_rights_contract.md:101-123`
- `actual_truth/contracts/SYSTEM_LAWS.md:72-74`

## Drift Evidence

- `backend/app/repositories/auth.py:71-114` still conditionally writes `onboarding_state`, `role_v2`, `role`, and `is_admin` into `app.profiles`.
- `backend/app/repositories/auth.py:293-300` still persists auth-subject fields through `_upsert_profile_row`.
- `backend/app/repositories/profiles.py:47` and `backend/app/repositories/profiles.py:64-65` still expose profile-driven onboarding mutation.

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

1. Strip `_upsert_profile_row` of any onboarding or role writes so it persists profile projection fields only.
2. Remove `onboarding_state` as a writable parameter from `backend/app/repositories/profiles.py.update_profile`.
3. Keep canonical subject creation and mutation only in `app.auth_subjects`.
4. Rewrite tests, fixtures, and scripts that mutate `app.profiles.role_v2` or `app.profiles.is_admin` so they use `app.auth_subjects` or canonical admin approval instead.

## Acceptance Criteria

- No Auth + Onboarding write path persists onboarding or role authority through `app.profiles`.
- Register request rejects `referral_code`.
- No Auth + Onboarding write path redeems a referral or grants membership through `/auth/register`.
- Profile update surfaces cannot mutate onboarding or role authority.
- No repository write path invents alternate field authority or fallback write behavior.

## Stop Conditions

- Stop if referral behavior still remains coupled to `/auth/register` after repair or if a required post-auth referral redemption surface is missing from the repo state required to preserve canonical referral behavior.
- Stop if any hidden repository helper reintroduces auth-subject fields into `app.profiles`.

## Out Of Scope

- Membership plan semantics
- Stripe behavior
- Course-access logic
