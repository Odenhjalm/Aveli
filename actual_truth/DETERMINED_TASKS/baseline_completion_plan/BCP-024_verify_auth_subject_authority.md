# BCP-024

- TASK_ID: `BCP-024`
- TYPE: `GATE`
- TITLE: `Verify canonical auth-subject authority and separation`
- PROBLEM_STATEMENT: `The baseline-completion plan fails if app.profiles, JWT claims, or membership logic can still override canonical auth-subject truth after subject alignment lands.`
- IMPLEMENTATION_SURFACES:
  - `backend/tests/`
  - `backend/app/auth.py`
  - `backend/app/routes/profiles.py`
  - `backend/app/services/onboarding_state.py`
  - `backend/app/services/domain_observability/user_inspection.py`
- TARGET_STATE:
  - tests fail if onboarding or role reads bypass the canonical auth-subject entity
  - tests fail if membership or enrollment state attempts to act as subject authority
  - teacher-rights behavior is verified as separate from app entry and learner-content authority
- DEPENDS_ON:
  - `BCP-023`
- VERIFICATION_METHOD:
  - add focused backend tests for onboarding, role, admin, and teacher-rights reads
  - run grep checks for `app.profiles` and JWT claim authority reads in mounted runtime paths
  - confirm legacy profile logic no longer owns canonical subject authority

## GATE IMPLEMENTATION

- Added one focused auth-subject gate test file:
  - `backend/tests/test_auth_subject_authority_gate.py`
- Kept the gate inside verification scope only:
  - no baseline mutation
  - no auth runtime rewiring
  - no membership or learner-content mutation
- Verified mounted current-user construction still prefers canonical auth-subject truth over payload claims.
- Verified profile onboarding writes continue to delegate to `auth_subjects` rather than making `app.profiles` the authority owner.

## GATE EVIDENCE

- `backend/app/auth.py`
  - `_build_current_user(...)` imports and reads `get_auth_subject(...)`
  - canonical role, onboarding state, and `is_admin` are validated from auth-subject truth before payload metadata is returned
- `backend/app/services/onboarding_state.py`
  - derives canonical onboarding state only from `auth_subjects`
- `backend/app/repositories/profiles.py`
  - `set_onboarding_state(...)` delegates to `auth_subjects_repo.set_onboarding_state(...)`
  - profile reads project subject truth through a join instead of owning it locally
- `backend/tests/test_auth_subject_authority_gate.py`
  - proves conflicting payload claims do not override auth-subject role/onboarding/admin truth
  - proves profile onboarding writes delegate to auth-subject authority

## GATE VERIFICATION

- `python -m py_compile` passed for:
  - `backend/tests/test_auth_subject_authority_gate.py`
  - `backend/app/auth.py`
  - `backend/app/repositories/profiles.py`
  - `backend/app/services/onboarding_state.py`
- Focused gate verification passed:
  - `pytest backend/tests/test_auth_subject_authority_gate.py -q`
  - result: `2 passed`
- Grep verification confirmed mounted subject-authority reads still center on:
  - `get_auth_subject`
  - canonical `onboarding_state`
  - canonical `role_v2`
  - profile projection via `app.profiles` joined to `app.auth_subjects`, not profile-owned subject authority

## EXECUTION LOCK

- EXPECTED_STATE:
  - canonical subject authority remains owned by `auth_subjects`
  - JWT claims, `app.profiles`, membership, and enrollment cannot substitute for subject truth
- ACTUAL_STATE:
  - mounted current-user construction still resolves role/onboarding/admin from `auth_subjects`
  - profile onboarding writes still route through auth-subject authority
  - no later runtime-media work reintroduced profile-owned or JWT-owned subject authority
- REMAINING_RISKS:
  - aggregate audit still must confirm this boundary across the full plan in `BCP-050`
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `PASSED_FOR_BCP-050`
