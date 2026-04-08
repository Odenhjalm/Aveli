# BCP-013

- TASK_ID: `BCP-013`
- TYPE: `OWNER`
- TITLE: `Align mounted app-entry reads and writes to canonical app.memberships`
- PROBLEM_STATEMENT: `Runtime app-entry behavior still risks drifting through onboarding checks, profile-derived assumptions, and legacy membership helpers. Once the baseline owns app.memberships, mounted runtime paths must consume that authority directly instead of preserving parallel app-entry logic.`
- IMPLEMENTATION_SURFACES:
  - `backend/app/repositories/memberships.py`
  - `backend/app/services/onboarding_state.py`
  - `backend/app/routes/domain_observability_mcp.py`
  - `backend/app/services/domain_observability/user_inspection.py`
  - mounted auth and app-shell entry routes that gate membership access
- TARGET_STATE:
  - mounted app-entry checks read canonical `app.memberships` only
  - onboarding completion no longer grants or denies app entry
  - `course_enrollments` no longer grant or deny app entry
  - app-entry mutation and synchronization paths target canonical membership authority only
- DEPENDS_ON:
  - `BCP-012`
- VERIFICATION_METHOD:
  - grep mounted runtime for app-entry checks that read onboarding, profiles, or enrollments as authority
  - confirm all app-entry reads resolve through canonical membership accessors
  - confirm no new fallback path is introduced

## OWNER IMPLEMENTATION

- Updated `backend/app/repositories/memberships.py` so canonical app-entry reads now resolve through the baseline-owned membership shape:
  - `membership_id`
  - `user_id`
  - `status`
  - `end_date`
  - `created_at`
  - `updated_at`
- Removed the explicit legacy `app.subscriptions` fallback from `get_latest_subscription()`.
- Kept non-authority billing fields as optional compatibility pass-through only when they still exist on the active schema, without letting them drive app-entry truth.
- Updated `backend/app/routes/api_auth.py` and `backend/app/routes/api_profiles.py` so `membership_active` is derived directly from the membership row via canonical membership helpers.
- Updated `backend/app/routes/domain_observability_mcp.py` and `backend/app/services/domain_observability/user_inspection.py` so observability explicitly reports `memberships` as app-entry authority.

## OWNER EVIDENCE

- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-012_append_baseline_app_memberships_authority.md`
  - already made baseline-owned `app.memberships` canonical above the protected slot boundary
  - already locked the minimum canonical membership shape
- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-011_lock_app_entry_membership_boundary.md`
  - already proved onboarding, subject, and learner-content state cannot substitute for app entry
- `Aveli_System_Decisions.md`
  - fixes app-access authority as `memberships`
  - forbids duplicate app-access authorities parallel to `memberships`
- `backend/app/routes/api_auth.py` and `backend/app/routes/api_profiles.py`
  - were already reading `app.memberships` for `membership_active`, but still depended on a repository query that assumed Stripe-era fields
- `backend/app/repositories/memberships.py`
  - previously selected Stripe-era fields unconditionally and retained an explicit legacy `app.subscriptions` fallback helper
- Deterministic inference used by this task:
  - optional Stripe-era membership columns may remain readable or writable as non-authority compatibility data when present on the active schema, but app-entry truth must remain derived only from canonical membership status and end-date semantics

## OWNER VERIFICATION

- Ran `python -m py_compile` on all touched runtime files and confirmed no syntax errors.
- Grepped the aligned app-entry surfaces and confirmed:
  - `api_auth.py` reads `repositories.get_membership(...)`
  - `api_profiles.py` reads `repositories.get_membership(...)`
  - both routes compute `membership_active` from `is_membership_row_active(membership)`
- Grepped the touched repository surfaces and confirmed:
  - the explicit `_get_legacy_subscription` fallback path is removed
  - no touched app-entry route consults `course_enrollments` as app-entry authority
- Verified observability now reports:
  - `app_entry_authority = memberships`
  - membership-present and membership-active state as explicit truth-source output

## EXECUTION LOCK

- EXPECTED_STATE:
  - mounted app-entry reads use canonical `app.memberships` only
  - onboarding completion and course enrollment do not grant or deny app entry
  - no legacy subscription fallback remains on the app-entry repository path
- ACTUAL_STATE:
  - membership repository reads are now canonical-shape safe across the current schema transition
  - auth/profile routes derive `membership_active` directly from the membership row
  - observability exposes `memberships` as app-entry authority explicitly
- REMAINING_RISKS:
  - onboarding-state derivation still lives on legacy profile authority and will be realigned in `BCP-023`
  - Stripe and billing flows still carry non-authority compatibility handling outside app-entry scope
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `LOCKED_FOR_BCP-014`
