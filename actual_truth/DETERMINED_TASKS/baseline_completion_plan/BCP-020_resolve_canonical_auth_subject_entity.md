# BCP-020

- TASK_ID: `BCP-020`
- TYPE: `OWNER`
- TITLE: `Resolve the canonical auth-subject entity above Supabase Auth`
- PROBLEM_STATEMENT: `The locked direction requires a separate canonical subject-entity above Supabase Auth, but the authoritative source set does not yet define the exact entity boundary, binding field, or minimum non-auth field set beyond onboarding and role authority. Current runtime still reads those fields from app.profiles and JWT claims, which would otherwise force legacy reuse or field invention.`
- IMPLEMENTATION_SURFACES:
  - `actual_truth/contracts/onboarding_teacher_rights_contract.md`
  - `Aveli_System_Decisions.md`
  - `aveli_system_manifest.json`
  - `backend/app/repositories/auth.py`
  - `backend/app/repositories/profiles.py`
  - `backend/app/auth.py`
- TARGET_STATE:
  - one canonical auth-subject entity above Supabase Auth is resolved
  - the minimum authority shape includes only the justified subject binding plus `onboarding_state`, `role_v2`, `role`, and `is_admin`
  - membership authority and learner-content authority remain explicitly separate from the auth-subject entity
  - teacher-rights mutation remains separate unless additional authority is explicitly justified by primary sources
- DEPENDS_ON:
  - `none`
- VERIFICATION_METHOD:
  - confirm the resolved entity can be derived from contracts and DECISIONS without returning to legacy `app.profiles` doctrine
  - confirm no extra subject field is introduced without authoritative evidence
  - stop if the subject binding above Supabase Auth is still ambiguous

## RESOLVED CANONICAL AUTH-SUBJECT ENTITY

- AUTH_SUBJECT_ENTITY_NAME:
  - `app.auth_subjects`
  - inference from the task's canonical `auth-subject` concept and the repo's plural app-entity naming pattern, used only because the primary sources require a separate non-profile subject owner but do not provide a pre-existing table name
- AUTH_SUBJECT_BINDING_FIELD:
  - `user_id`
  - `user_id` is the sole subject binding above Supabase Auth
  - the binding remains a soft external reference to `auth.users.id`
- AUTH_SUBJECT_AUTHORITY_FIELDS:
  - `onboarding_state`
  - `role_v2`
  - `role`
  - `is_admin`

## RESOLVED BOUNDARY RULES

- `app.auth_subjects` owns subject-level onboarding and role authority only.
- `role_v2` remains canonical role truth.
- `role` remains compatibility support only and does not own role truth.
- `is_admin` remains a separate admin override and does not create teacher rights.
- Teacher-rights mutation remains separate from the entity boundary except where a canonical approval path writes the already-authorized `role_v2` field.
- JWT claims are transport or cache copies only and must not remain the canonical owner path for these fields.
- `app.profiles` may remain as a presentation or transition surface, but it is not the canonical owner for auth-subject authority.

## EXPLICIT EXCLUSIONS

- `display_name`
- `bio`
- `photo_url`
- `avatar_media_id`
- `email`
- `stripe_customer_id`
- provider identity fields
- last-login tracking fields
- `memberships`
- `course_enrollments`
- lesson-content access state

## RESOLUTION EVIDENCE

- CONTRACT:
  - `onboarding_state`, `role_v2`, `role`, and `is_admin` are the primary authority fields for onboarding and teacher-rights domains.
  - `onboarding_state` belongs to the subject user's canonical onboarding lifecycle.
  - `role_v2` belongs to system-governed role authority.
  - `role` belongs to compatibility support only.
  - `is_admin` belongs to admin-governed override authority.
  - `onboarding_state` does not replace membership authority for app entry.
- DECISIONS:
  - app-entry authority is `memberships`, not subject authority.
  - course-content access authority is `course_enrollments`, not subject authority.
  - `auth.users` remains an external dependency and external references must not use database foreign keys.
  - auth is a relationship entry and must not be redesigned inside the substrate layer during this phase.
- MANIFEST:
  - `app_access_authority = memberships`
  - `canonical_protected_course_content_access_authority = course_enrollments`
- CURRENT RUNTIME EVIDENCE:
  - current runtime stores authority fields on `app.profiles`, but the same surface also carries presentation, media, provider, and billing-adjacent fields
  - current runtime still reads role and admin fallback from JWT payload and metadata in `backend/app/auth.py`
  - protected baseline slots do not own `app.profiles` or any separate auth-subject entity
  - current remote schema `app.profiles` lacks `onboarding_state`, proving legacy profile shape is not a stable canonical owner boundary

## EXECUTION LOCK

- EXPECTED_CANONICAL_STATE:
  - one dedicated subject entity above Supabase Auth owns only subject binding plus `onboarding_state`, `role_v2`, `role`, and `is_admin`
  - app entry and learner-content access remain outside that entity
- ACTUAL_STATE_BEFORE_ACTION:
  - no baseline-owned auth-subject entity existed
  - runtime authority was split across `app.profiles` and JWT claims
  - legacy profile shape mixed subject authority with presentation and provider fields
- DECISION:
  - resolved and locked a separate canonical auth-subject entity as `app.auth_subjects` with `user_id` as the only justified binding field
- REMAINING_RISKS:
  - runtime still reads auth-subject authority from legacy `app.profiles` and JWT claims until `BCP-023`
  - baseline still lacks append-only ownership for `app.auth_subjects` until `BCP-022`
- LOCK_STATUS:
  - `LOCKED_FOR_BCP-021_AND_BCP-022`
