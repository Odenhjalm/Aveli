# BCP-014

- TASK_ID: `BCP-014`
- TYPE: `GATE`
- TITLE: `Verify that app.memberships is the sole app-entry authority`
- PROBLEM_STATEMENT: `The canonical baseline-completion plan fails if app entry can still be granted or denied by onboarding, role state, course enrollment, or any legacy profile path after membership alignment lands.`
- IMPLEMENTATION_SURFACES:
  - `backend/tests/`
  - `backend/app/repositories/memberships.py`
  - `backend/app/services/onboarding_state.py`
  - `backend/app/services/domain_observability/user_inspection.py`
- TARGET_STATE:
  - focused verification fails when app entry is attempted without canonical membership authority
  - focused verification fails when onboarding, role, or enrollment state attempts to substitute for app entry
  - domain observability and auth-adjacent reads report membership as app-entry authority only
- DEPENDS_ON:
  - `BCP-013`
- VERIFICATION_METHOD:
  - add focused backend tests for app-entry authority
  - run grep checks for onboarding, profile, and enrollment substitutions in app-entry code paths
  - confirm no mounted runtime path can enter the app without canonical membership authority

## GATE IMPLEMENTATION

- Added one focused app-entry gate test file:
  - `backend/tests/test_membership_app_entry_gate.py`
- Kept the gate inside verification scope only:
  - no baseline mutation
  - no repository or route rewiring
  - no new authority path
- Verified the mounted profile response continues to compute `membership_active` only from canonical membership truth.
- Verified domain observability continues to report:
  - app-entry authority = `memberships`
  - auth-subject authority = `auth_subjects`
  - enrolled-course presence does not substitute for app entry

## GATE EVIDENCE

- `backend/app/routes/api_profiles.py`
  - `_profile_response(...)` reads `memberships.get_membership(...)`
  - `membership_active` is derived only from `is_membership_row_active(...)`
- `backend/app/services/domain_observability/user_inspection.py`
  - `state_summary.app_entry_authority = memberships`
  - `truth_sources.app_entry.authority = memberships`
  - enrollment is tracked only under course truth, not app-entry truth
- `backend/app/services/onboarding_state.py`
  - onboarding derives from `auth_subjects`, not from membership or enrollment
- `backend/tests/test_membership_app_entry_gate.py`
  - proves teacher status plus completed onboarding do not substitute for membership-backed app entry
  - proves enrolled-course presence does not substitute for membership-backed app entry

## GATE VERIFICATION

- `python -m py_compile` passed for:
  - `backend/tests/test_membership_app_entry_gate.py`
  - `backend/app/routes/api_profiles.py`
  - `backend/app/services/domain_observability/user_inspection.py`
- Focused gate verification passed:
  - `pytest backend/tests/test_membership_app_entry_gate.py -q`
  - result: `2 passed`
- Grep verification confirmed the mounted app-entry observability path still cites:
  - `memberships.get_membership`
  - `app_entry_authority = memberships`
  - separate `courses.list_my_courses` tracking without course-entitlement substitution

## EXECUTION LOCK

- EXPECTED_STATE:
  - app entry remains governed only by canonical membership truth after `BCP-013`
  - onboarding, teacher state, and enrollment cannot substitute for app entry
- ACTUAL_STATE:
  - mounted profile response still reports `membership_active` only from `app.memberships`
  - domain observability still reports `memberships` as app-entry authority even when enrolled courses exist
  - no new substitution path was introduced during later runtime-media alignment work
- REMAINING_RISKS:
  - aggregate audit still must confirm the same boundary at plan level in `BCP-050`
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `PASSED_FOR_BCP-050`
