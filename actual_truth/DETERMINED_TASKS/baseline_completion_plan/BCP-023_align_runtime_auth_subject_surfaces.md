# BCP-023

- TASK_ID: `BCP-023`
- TYPE: `OWNER`
- TITLE: `Align mounted auth, onboarding, and teacher-rights surfaces to the canonical auth-subject entity`
- PROBLEM_STATEMENT: `Runtime code still reads onboarding and role authority from app.profiles and JWT claims. After baseline ownership exists, those runtime surfaces must move to the canonical auth-subject entity so that Supabase Auth remains substrate and legacy profile logic stops owning authority.`
- IMPLEMENTATION_SURFACES:
  - `backend/app/auth.py`
  - `backend/app/repositories/auth.py`
  - `backend/app/repositories/profiles.py`
  - `backend/app/routes/profiles.py`
  - `backend/app/services/onboarding_state.py`
  - `backend/app/permissions.py`
  - `backend/app/services/domain_observability/user_inspection.py`
- TARGET_STATE:
  - mounted runtime reads `onboarding_state`, `role_v2`, `role`, and `is_admin` from the canonical auth-subject entity
  - JWT claims stop acting as primary authority for those fields
  - `app.profiles` stops acting as the canonical owner for those authority fields
  - teacher-rights evaluation remains separate from membership and learner-content authority
- DEPENDS_ON:
  - `BCP-022`
- VERIFICATION_METHOD:
  - grep runtime for profile- or claim-based authority reads after alignment
  - confirm onboarding and role mutation flows target the canonical auth-subject entity
  - confirm teacher approval remains the only teacher-rights grant path

## OWNER IMPLEMENTATION

- Added `backend/app/repositories/auth_subjects.py` as the canonical runtime repository for `app.auth_subjects`.
- Rewired mounted auth-subject reads so runtime authority now comes from `app.auth_subjects`:
  - `backend/app/auth.py`
  - `backend/app/repositories/profiles.py`
  - `backend/app/models.py`
  - `backend/app/services/domain_observability/user_inspection.py`
- Rewired subject-authority writes so canonical onboarding/role/admin state is not created or mutated through `app.profiles`:
  - `backend/app/repositories/auth.py` now creates the canonical auth-subject row with explicit canonical values
  - `backend/app/routes/api_auth.py` now ensures `app.auth_subjects` and no longer inserts legacy onboarding/role/admin values into `app.profiles`
  - `backend/app/models.py` teacher approval now writes canonical role authority to `app.auth_subjects`
- Removed legacy onboarding-state derivation semantics from mounted runtime by turning `backend/app/services/onboarding_state.py` into a canonical auth-subject reader instead of a legacy state machine.

## OWNER EVIDENCE

- `actual_truth/contracts/onboarding_teacher_rights_contract.md`
  - fixes `onboarding_state` to `incomplete|completed`
  - fixes `role_v2`/`role` to `learner|teacher`
  - fixes `is_admin` as separate admin override
  - forbids invalid onboarding normalization and forbids admin authority from creating teacher rights
- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-020_resolve_canonical_auth_subject_entity.md`
  - resolves `app.auth_subjects` as the only canonical subject owner path
  - classifies JWT claims and `app.profiles` as transport/transition only
- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-021_lock_auth_subject_separation_boundary.md`
  - already locked membership and learner-content authority outside the auth-subject boundary
- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-022_append_baseline_auth_subject_authority.md`
  - already appended baseline ownership for `app.auth_subjects`

## OWNER VERIFICATION

- Runtime authority reads must now source `onboarding_state`, `role_v2`, `role`, and `is_admin` from `app.auth_subjects` rather than JWT claims or `app.profiles`.
- Onboarding runtime must no longer derive or persist legacy states such as `registered_unverified`, `verified_unpaid`, `access_active_profile_incomplete`, `access_active_profile_complete`, or `welcomed`.
- Teacher-rights evaluation must no longer grant teacher rights from `is_admin`, `teacher_permissions`, or `teacher_approvals` alone.
- Teacher approval remains the canonical grant path by mutating canonical role authority to `teacher`.
- `python -m py_compile` passed for:
  - `backend/app/repositories/auth_subjects.py`
  - `backend/app/repositories/__init__.py`
  - `backend/app/repositories/profiles.py`
  - `backend/app/repositories/auth.py`
  - `backend/app/auth.py`
  - `backend/app/models.py`
  - `backend/app/routes/auth.py`
  - `backend/app/routes/api_auth.py`
  - `backend/app/services/onboarding_state.py`
  - `backend/app/services/domain_observability/user_inspection.py`
- Grep verification passed:
  - no legacy onboarding states remain anywhere under `backend/app`
  - no `teacher_permissions` or legacy JWT-role owner writes remain anywhere under `backend/app`
  - no JWT claim chain for `role_v2`, `role`, or `is_admin` remains in `backend/app/auth.py`
  - no direct `app.profiles` subject-authority SQL remains under `backend/app`

## EXECUTION LOCK

- EXPECTED_STATE:
  - mounted auth, onboarding, and teacher-rights runtime paths read canonical subject authority from `app.auth_subjects`
  - signup and teacher approval mutate canonical subject authority through `app.auth_subjects`
  - legacy onboarding-state derivation and alternate teacher-rights grant paths are removed
- ACTUAL_STATE_AFTER_ACTION:
  - canonical auth-subject repository now exists and is consumed by mounted runtime
  - `backend/app/auth.py` resolves role/admin/onboarding from `app.auth_subjects`
  - `backend/app/repositories/auth.py` and `backend/app/routes/api_auth.py` ensure canonical auth-subject creation with explicit canonical values
  - `backend/app/models.py` teacher approval mutates `app.auth_subjects`, and alternate `teacher_permissions`/JWT metadata role grants are removed
  - `backend/app/services/onboarding_state.py` now reads only canonical `incomplete|completed`
- DECISION:
  - owner task passes
- REMAINING_RISKS:
  - gate coverage in `BCP-024` still needs focused tests to prevent future regressions in auth-subject authority reads
- LOCK_STATUS:
  - `LOCKED_FOR_BCP-024`
