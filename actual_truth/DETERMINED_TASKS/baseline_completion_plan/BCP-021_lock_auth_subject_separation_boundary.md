# BCP-021

- TASK_ID: `BCP-021`
- TYPE: `GATE`
- TITLE: `Lock the canonical auth-subject boundary before baseline work starts`
- PROBLEM_STATEMENT: `Append-only subject-entity work cannot start until the resolved auth-subject boundary proves that onboarding and role authority belong to one subject entity, separate from app entry, learner content access, and legacy profile semantics.`
- IMPLEMENTATION_SURFACES:
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-020_resolve_canonical_auth_subject_entity.md`
  - `actual_truth/contracts/onboarding_teacher_rights_contract.md`
  - `backend/app/repositories/profiles.py`
  - `backend/app/auth.py`
- TARGET_STATE:
  - one resolved auth-subject boundary exists
  - subject authority does not claim app-entry or course-content access
  - legacy `app.profiles` authority fields are marked for removal or isolation from runtime authority paths
  - downstream schema work can proceed without guessing the subject model
- DEPENDS_ON:
  - `BCP-020`
- VERIFICATION_METHOD:
  - assert that all four authority fields have one owner path
  - assert that membership and `course_enrollments` remain outside the auth-subject boundary
  - stop if legacy profile logic still acts as canonical subject truth

## GATE ASSERTIONS

- One auth-subject owner path exists for subject authority only:
  - entity: `app.auth_subjects`
  - binding: `user_id`
  - authority fields: `onboarding_state`, `role_v2`, `role`, `is_admin`
- App-entry authority remains outside the auth-subject boundary:
  - `app.memberships`
- Learner-content authority remains outside the auth-subject boundary:
  - `course_enrollments`
  - `current_unlock_position`
- Teacher-rights separation remains preserved:
  - `role_v2` owns canonical role truth
  - `role` is compatibility only
  - `is_admin` is admin override only
  - teacher-rights mutation remains separate except where canonical approval writes the already-authorized role field
- JWT claims and legacy `app.profiles` data may exist as transport or transition surfaces only and do not remain canonical owner paths.

## GATE EVIDENCE

- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-020_resolve_canonical_auth_subject_entity.md`
  - already resolves one subject entity, one binding, and one minimum authority shape
  - already excludes membership and learner-content authority from the auth-subject boundary
- `actual_truth/contracts/onboarding_teacher_rights_contract.md`
  - fixes `onboarding_state`, `role_v2`, `role`, and `is_admin` as the canonical authority fields for the subject domain
  - keeps teacher rights separate from admin authority
  - states that `onboarding_state` does not replace membership authority for app entry
- `Aveli_System_Decisions.md`
  - fixes `memberships` as app-entry authority
  - fixes `course_enrollments` as canonical learner-content authority
  - keeps `auth.users` as an external dependency and forbids database foreign keys for that binding
- `aveli_system_manifest.json`
  - `app_access_authority = memberships`
  - `canonical_protected_course_content_access_authority = course_enrollments`
- `backend/app/repositories/profiles.py`
  - still reads and writes onboarding plus role/admin-adjacent fields on `app.profiles`
  - also mixes those authority fields with presentation fields such as `display_name`, `bio`, `photo_url`, and `avatar_media_id`
- `backend/app/auth.py`
  - still derives `role_v2` and `is_admin` from JWT payload and metadata fallback chains
  - therefore demonstrates mounted drift, not canonical ownership
- `backend/app/repositories/auth.py`
  - still inserts auth-subject authority fields into `app.profiles`, confirming that mounted runtime has not yet been realigned
- remote-schema mismatch evidence only:
  - legacy `app.profiles` remains a mixed surface and therefore cannot stand as the canonical auth-subject owner

## GATE DECISION

- The resolved auth-subject boundary is deterministic enough for append-only baseline ownership work to proceed.
- Membership authority and learner-content authority remain materially outside the auth-subject boundary.
- Legacy `app.profiles` and JWT logic are now explicitly classified as transition or drift paths rather than canonical subject truth.
- Because the boundary has been resolved and isolated in the task artifact, mounted legacy usage is a later alignment concern, not a blocker for `BCP-022`.

## EXECUTION LOCK

- EXPECTED_GATE_STATE:
  - one blocking-ready auth-subject model exists above Supabase Auth
  - downstream baseline work may append only the resolved subject entity without guessing field ownership or collapsing into profile doctrine
- ACTUAL_GATE_STATE_BEFORE_ACTION:
  - `BCP-020` had resolved the boundary, but this gate artifact had not yet certified separation from membership, learner-content, and legacy profile semantics
  - mounted runtime still relied on `app.profiles` and JWT fallback for subject authority
- DECISION:
  - gate passes
- REMAINING_RISKS:
  - mounted runtime still reads auth-subject authority from legacy `app.profiles` and JWT claims until `BCP-023`
  - baseline still lacks append-only ownership for `app.auth_subjects` until `BCP-022`
- LOCK_STATUS:
  - `PASSED_FOR_BCP-022`
