# AUTH_ONBOARDING_CONTRACT_ALIGNMENT

`input(task="Construct deterministic implementation task tree for Auth + Onboarding", mode="generate")`

## Scope

- Route and execution authority is limited to `actual_truth/contracts/auth_onboarding_contract.md`.
- Onboarding and role field authority is limited to `actual_truth/contracts/onboarding_teacher_rights_contract.md`.
- System fallback and authority-boundary law is limited to `actual_truth/contracts/SYSTEM_LAWS.md`.
- DECISIONS authority is limited to `actual_truth/Aveli_System_Decisions.md`.
- Repository code is EMERGENT_TRUTH only and is used here as diff evidence, not as authority.
- Membership, Stripe, and course-access logic stay out of scope except where they leak into Auth + Onboarding surfaces.

## Canonical Truth Layers

- EXECUTION CONTRACT: `actual_truth/contracts/auth_onboarding_contract.md`
- DOMAIN CONTRACT: `actual_truth/contracts/onboarding_teacher_rights_contract.md`
- SYSTEM LAW: `actual_truth/contracts/SYSTEM_LAWS.md`
- DECISIONS:
  - `actual_truth/Aveli_System_Decisions.md:96`
  - `actual_truth/Aveli_System_Decisions.md:413`
  - `actual_truth/Aveli_System_Decisions.md:490`

## Retrieval Queries

- `/auth/me`, `/profiles/me`, `/auth/request-password-reset`, `/auth/forgot-password`
- `/admin/teachers/`, `/admin/teacher-requests/`
- `api_auth`, `api_profiles`, `schemas.py`, `schemas/__init__.py`
- `registered_unverified`, `verified_unpaid`, `access_active_profile_incomplete`, `access_active_profile_complete`, `welcomed`
- `role_v2`, `role`, `is_admin`, `is_teacher`, `membership_active`, `email_verified`, `referral_code`

## Evaluation Criteria

- All mounted and consumed Auth + Onboarding surfaces align with `actual_truth/contracts/auth_onboarding_contract.md`.
- `auth.users` remains identity authority, `app.auth_subjects` remains subject authority, and `app.profiles` remains projection-only authority under `actual_truth/contracts/onboarding_teacher_rights_contract.md`.
- No legacy endpoint, duplicate authority, admin-as-teacher shortcut, or non-canonical onboarding state survives; any remaining `role` fallback matches canonical compatibility law.
- Materialized tasks preserve explicit `TYPE`, explicit `DEPENDS_ON`, and a deterministic topological order.

## Retrieval Note

- `semantic_search` was not exposed in this session.
- Contract-scoped repo text search was used as EMERGENT_TRUTH evidence.

## Drift Register

### DRIFT-001

- Classification: `REPLACE`
- Contract rule:
  - `actual_truth/contracts/auth_onboarding_contract.md:27-40`
  - `actual_truth/contracts/auth_onboarding_contract.md:164-167`
- Evidence:
  - `backend/app/main.py:173` mounts `auth.router`
  - `backend/app/main.py:175` mounts `profiles.router`
  - `backend/app/main.py` now mounts `admin.router`; remaining drift in this register is legacy `/admin/teachers/*` callers and old current-user/password-reset consumers
  - `backend/app/routes/admin.py:53` and `backend/app/routes/admin.py:68` still define forbidden `/admin/teachers/*` handlers beside canonical `/admin/teacher-requests/*`
  - `frontend/lib/api/api_paths.dart:4` and `frontend/lib/api/api_paths.dart:7` still point frontend current-user and password-reset traffic at forbidden paths
  - `frontend/lib/features/community/data/admin_repository.dart:22` and `frontend/lib/features/community/data/admin_repository.dart:30` still call `/admin/teachers/*`
- Owning task: `AOC-001`

### DRIFT-002

- Classification: `COLLAPSE`
- Contract rule:
  - `actual_truth/contracts/auth_onboarding_contract.md:162-169`
  - `actual_truth/contracts/SYSTEM_LAWS.md:9-15`
- Evidence:
  - `backend/app/routes/api_auth.py:463` defines forbidden `/request-password-reset`
  - `backend/app/routes/api_auth.py:617` and `backend/app/routes/api_profiles.py:46` define duplicate current-user surfaces
  - `backend/app/schemas.py` and `backend/app/schemas/__init__.py` both define auth/profile request and response models
  - `backend/app/schemas/__init__.py:98-100` still carries `email_verified`, `membership_active`, and `is_teacher` into the shared profile schema
- Owning task: `AOC-002`

### DRIFT-003

- Classification: `ISOLATE`
- Contract rule:
  - `actual_truth/contracts/auth_onboarding_contract.md:162-169`
  - `actual_truth/contracts/SYSTEM_LAWS.md:61-62`
- Evidence:
  - `backend/tests/test_onboarding_state.py:10` imports `app.routes.api_auth`
  - `backend/tests/test_membership_app_entry_gate.py:12` imports `app.routes.api_profiles`
  - `backend/test_email_verification.py:12` imports `app.routes.api_auth as api_auth_routes`
  - `backend/tests/conftest.py:139` imports `api_auth`
- Owning task: `AOC-003`

### DRIFT-004

- Classification: `REPLACE`
- Contract rule:
  - `actual_truth/contracts/auth_onboarding_contract.md:50-57`
  - `actual_truth/contracts/auth_onboarding_contract.md:156-160`
  - `actual_truth/contracts/onboarding_teacher_rights_contract.md:101-123`
  - `actual_truth/contracts/SYSTEM_LAWS.md:72-74`
- Evidence:
  - `backend/app/repositories/auth.py:71-114` still conditionally writes `onboarding_state`, `role_v2`, `role`, and `is_admin` into `app.profiles`
  - `backend/app/repositories/auth.py:293-300` still persists auth-subject fields through `_upsert_profile_row`
  - `backend/app/repositories/profiles.py:47` and `backend/app/repositories/profiles.py:64-65` still expose profile-driven onboarding mutation
  - auth-side referral coupling is already removed; active drift in this register is limited to profile-authority leakage through `app.profiles`
- Owning task: `AOC-004`

### DRIFT-005

- Classification: `REMOVE`
- Contract rule:
  - `actual_truth/contracts/auth_onboarding_contract.md:130-136`
  - `actual_truth/contracts/auth_onboarding_contract.md:156-160`
  - `actual_truth/contracts/onboarding_teacher_rights_contract.md:67-69`
  - `actual_truth/contracts/onboarding_teacher_rights_contract.md:91-99`
  - `actual_truth/contracts/onboarding_teacher_rights_contract.md:193-199`
- Resolved note:
  - `backend/app/routes/auth.py:118-142` now emits compatibility-only `role` and `is_admin` claims, not `is_teacher`
  - `backend/tests/test_auth_subject_authority_gate.py:1-172` proves token payload claims are non-authoritative in mounted backend scope
- Evidence:
  - `backend/app/models.py:556`, `696`, `785`, and `2109` still treat `is_admin` as teacher authority
  - `frontend/lib/data/models/profile.dart:8-16` and `frontend/lib/data/models/profile.dart:151-162` still carry `user`, `professional`, five legacy onboarding states, and non-canonical `role` handling
  - `frontend/lib/core/routing/app_router.dart:195-276` still routes on legacy onboarding states
- Owning task: `AOC-005`

### DRIFT-006

- Classification: `REPLACE`
- Contract rule:
  - `actual_truth/contracts/auth_onboarding_contract.md:191-198`
- Evidence:
  - `backend/app/services/email_verification.py:15-17` uses English email subjects
  - `backend/app/services/email_verification.py:42` and `backend/app/services/email_verification.py:81` use English email body text
  - `backend/app/routes/auth.py:158`, `202`, and `212` use English runtime detail strings
  - `backend/app/permissions.py:22` and `backend/app/permissions.py:36` use English permission errors
  - `backend/app/routes/profiles.py:24`, `40`, `52`, and `62` use English profile errors
- Owning task: `AOC-006`

### DRIFT-007

- Classification: `REMOVE`
- Contract rule:
  - `actual_truth/contracts/auth_onboarding_contract.md:27-40`
  - `actual_truth/contracts/auth_onboarding_contract.md:130-136`
  - `actual_truth/contracts/auth_onboarding_contract.md:156-160`
  - `actual_truth/contracts/onboarding_teacher_rights_contract.md:193-199`
  - `actual_truth/contracts/SYSTEM_LAWS.md:72-74`
- Evidence:
  - `backend/tests/utils.py:27` still reads `/auth/me`
  - `backend/tests/test_admin_permissions.py:119-138` still exercises `/admin/teachers/*`
  - `backend/tests/test_onboarding_state.py:16-487` still asserts legacy states and legacy route-module behavior
  - `backend/scripts/seed_local_course_editor_substrate.py:230-254` still seeds `welcomed`
  - `frontend/test/routing/app_router_test.dart:158-229` still validates five-state routing
  - `frontend/test/unit/profile_test.dart:12-14` still asserts `is_teacher`, `membership_active`, and `email_verified`
- Owning task: `AOC-007`

## Materialized Task Order

1. `AOC-001` replace mounted entrypoints with the canonical inventory
2. `AOC-002` collapse duplicate auth/profile surfaces and schema authority
3. `AOC-003` isolate legacy shadow modules and imports from validation flow
4. `AOC-004` replace profile-authority leakage with subject-authority writes only
5. `AOC-005` remove invalid teacher inference, legacy onboarding state, and cross-domain auth fields while preserving canonical role compatibility fallback
6. `AOC-006` replace remaining non-Swedish Auth + Onboarding text on kept surfaces
7. `AOC-007` rewrite validation gates, tests, fixtures, and scripts to canonical truth only
8. `AOC-008` run the aggregate grep and route-inventory gate
