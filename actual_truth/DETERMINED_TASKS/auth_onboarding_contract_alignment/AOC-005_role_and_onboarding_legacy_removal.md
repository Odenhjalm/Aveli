# AOC-005_ROLE_AND_ONBOARDING_LEGACY_REMOVAL

- TYPE: `OWNER`
- TITLE: `Remove invalid teacher inference, legacy onboarding-state, and cross-domain auth fields while preserving canonical role compatibility fallback`
- DOMAIN: `runtime authority consumption`
- CLASSIFICATION: `REMOVE`

## Problem Statement

The current contract layer preserves compatibility fallback through `role` when `role_v2` is missing or invalid, but it forbids treating `role` as independent truth, forbids teacher-rights inference from `is_admin`, and locks onboarding to `incomplete -> completed`. The repo still carries admin-as-teacher shortcuts, invalid JWT teacher authority, five onboarding states, non-canonical role values, and cross-domain auth fields such as `membership_active`, `is_teacher`, and `email_verified`.

## Primary Authority Reference

- `actual_truth/contracts/auth_onboarding_contract.md:130-136`
- `actual_truth/contracts/auth_onboarding_contract.md:156-160`
- `actual_truth/contracts/onboarding_teacher_rights_contract.md:67-69`
- `actual_truth/contracts/onboarding_teacher_rights_contract.md:91-99`
- `actual_truth/contracts/onboarding_teacher_rights_contract.md:193-199`
- `actual_truth/contracts/SYSTEM_LAWS.md:72-74`

## Drift Evidence

- `backend/app/routes/auth.py:119-129` still emits `role` and `is_teacher` token claims.
- `backend/app/models.py:556`, `696`, `785`, and `2109` still treat `is_admin` as teacher authority.
- `frontend/lib/core/auth/auth_claims.dart:21` still trusts JWT `is_teacher`.
- `frontend/lib/data/models/profile.dart:8-16` still defines five onboarding states and non-canonical `user` and `professional` roles.
- `frontend/lib/data/models/profile.dart:151-162` still treats `role` as a first-class frontend enum source instead of a constrained compatibility field.
- `frontend/lib/core/routing/app_router.dart:195-276` still routes on legacy onboarding states.
- `frontend/lib/features/studio/data/studio_repository.dart:380` still requires `is_teacher`.
- `frontend/lib/mvp/api_client.dart:151` still falls back to `role` and `student`.

## Implementation Surfaces Affected

- `backend/app/auth.py`
- `backend/app/models.py`
- `backend/app/routes/auth.py`
- `frontend/lib/core/auth/auth_claims.dart`
- `frontend/lib/core/routing/app_router.dart`
- `frontend/lib/data/models/profile.dart`
- `frontend/lib/domain/models/user_access.dart`
- `frontend/lib/features/studio/data/studio_repository.dart`
- `frontend/lib/mvp/api_client.dart`
- `backend/tests`
- `frontend/test`
- `backend/scripts`

## DEPENDS_ON

- `AOC-003`
- `AOC-004`

## Exact Implementation Steps

1. Preserve the canonical runtime read order: validate `role_v2` first, then validate and use `role` only as compatibility fallback when `role_v2` is missing or invalid.
2. Remove any treatment of `role` as independent truth, and constrain compatibility handling to canonical legacy values only.
3. Make teacher-rights reads depend on effective non-admin role authority only; `is_admin` stays admin-only and does not create teacher rights.
4. Remove `is_teacher` as a JWT authority input and stop frontend claim parsing from using it.
5. Collapse frontend onboarding state handling to `incomplete` and `completed` only.
6. Remove `user`, `professional`, `student`, and any other non-canonical role values from Auth + Onboarding frontend models and routing logic.
7. Remove `membership_active`, `is_teacher`, and `email_verified` from Auth + Onboarding request or response consumption paths.
8. Rewrite tests, seeds, and scripts to canonical role values (`learner`, `teacher`) and canonical onboarding values (`incomplete`, `completed`) only; any compatibility-fallback test must keep `role_v2 -> role` precedence intact.

## Acceptance Criteria

- Effective role reads use `role_v2` first and use `role` only as validated compatibility fallback.
- No Auth + Onboarding runtime path infers teacher rights from `is_admin` or JWT `is_teacher`.
- No Auth + Onboarding runtime path uses onboarding states outside `incomplete` and `completed`.
- Frontend Auth + Onboarding logic uses canonical effective-role semantics and no longer treats `role` as a second authority.
- Cross-domain auth fields do not leak into current-profile truth.

## Stop Conditions

- Stop if another domain still depends on `membership_active`, `is_teacher`, or legacy onboarding states to function; that dependency must be isolated away from Auth + Onboarding truth.
- Stop if repairing compatibility fallback handling would silently broaden access instead of narrowing it to contract truth.

## Out Of Scope

- Non-auth teacher directory presentation outside contract-scoped fields
- Non-auth profile media presentation
