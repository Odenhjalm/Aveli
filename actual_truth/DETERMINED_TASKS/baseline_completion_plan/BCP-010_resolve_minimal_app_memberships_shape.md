# BCP-010

- TASK_ID: `BCP-010`
- TYPE: `OWNER`
- TITLE: `Resolve the minimum canonical app.memberships authority shape`
- PROBLEM_STATEMENT: `The locked direction fixes app.memberships as the canonical app-entry authority, but the authoritative source set does not yet define the minimum field contract that app entry may read. Current runtime evidence also mixes Stripe-era membership fields with onboarding and enrollment-adjacent checks, so execution would otherwise invent schema or preserve duplicate authority.`
- IMPLEMENTATION_SURFACES:
  - `Aveli_System_Decisions.md`
  - `aveli_system_manifest.json`
  - `actual_truth/contracts/onboarding_teacher_rights_contract.md`
  - `backend/app/repositories/memberships.py`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql`
- TARGET_STATE:
  - the minimum canonical field set for app entry is explicitly resolved for `app.memberships`
  - authority fields are separated from billing, Stripe, or compatibility fields
  - onboarding, `course_enrollments`, and auth-subject fields are explicitly excluded from app-entry authority
  - the resolved shape is sufficient to drive append-only baseline work without inventing unsupported fields
- DEPENDS_ON:
  - `none`
- VERIFICATION_METHOD:
  - compare the resolved shape against DECISIONS, MANIFEST, contracts, and current runtime evidence
  - confirm every authority field has source evidence
  - confirm no non-membership field can grant app entry after resolution

## RESOLVED CANONICAL AUTHORITY SHAPE

- APP_ENTRY_AUTHORITY_OWNER:
  - `app.memberships`
- APP_ENTRY_AUTHORITY_FIELDS:
  - `user_id`
  - `status`
  - `end_date`
- APP_ENTRY_STRUCTURAL_SUPPORT_FIELDS:
  - `membership_id`
  - `created_at`
  - `updated_at`
- APP_ENTRY_NON_AUTHORITY_FIELDS:
  - `plan_interval`
  - `price_id`
  - `stripe_customer_id`
  - `stripe_subscription_id`
  - `start_date`

## RESOLVED VALID-STATE BOUNDARY

- A membership row may grant app entry only when:
  - `status IN ('active', 'trialing')`
  - `end_date IS NULL OR end_date > now()`
- App entry is denied when:
  - no `app.memberships` row exists for the subject `user_id`
  - `status` is missing, invalid, or outside `('active', 'trialing')`
  - `end_date` is present and not in the future
- `start_date` is not part of app-entry authority in the current canonical resolution.
- Onboarding, role, admin, and learner-content authorities must not substitute for membership state.

## EXPLICIT EXCLUSIONS

- `onboarding_state`
- `role`
- `role_v2`
- `is_admin`
- `course_enrollments`
- `current_unlock_position`
- lesson-content access state
- Stripe billing references
- compatibility aliases such as `subscription`

## RESOLUTION EVIDENCE

- DECISIONS:
  - `membership` is the canonical app-access term and app-access authority is `memberships`.
  - `membership` is required to pass landing and enter the app.
  - `course_enrollments` own learner-content access and must remain separate from app entry.
- MANIFEST:
  - `app_access_authority = memberships`
  - `membership_scope = global`
  - `membership_required_for_app_entry = true`
  - `membership_alone_never_grants_canonical_protected_course_content_access = true`
- CONTRACT:
  - `onboarding_state` does not replace membership authority for app entry.
- CURRENT RUNTIME EVIDENCE:
  - mounted membership activity checks grant only `status IN ('active', 'trialing')` with future or null `end_date`
  - referral signup can create an active membership with `plan_interval = referral` and `price_id = referral_grant`, proving billing fields are not app-entry authority
  - current remote schema constrains `plan_interval` to month/year and adds an `auth.users` foreign key, which conflicts with current runtime evidence and external-reference law, so those fields and constraints cannot define canonical app-entry authority

## EXECUTION LOCK

- EXPECTED_CANONICAL_STATE:
  - one deterministic app-entry authority path exists through `app.memberships`
  - the minimum authority read boundary is explicit and excludes onboarding, role, admin, enrollment, and billing drift
- ACTUAL_STATE_BEFORE_ACTION:
  - the task file did not resolve the minimum `app.memberships` authority shape
  - runtime code mixed authority reads with Stripe-era membership fields and onboarding-derived app-entry flow
- DECISION:
  - resolved and locked the minimum canonical app-entry authority boundary in this task artifact
- REMAINING_RISKS:
  - mounted runtime still derives onboarding flow from membership outcome until `BCP-013`
  - baseline still lacks append-only ownership for `app.memberships` until `BCP-012`
- LOCK_STATUS:
  - `LOCKED_FOR_BCP-011_AND_BCP-012`
