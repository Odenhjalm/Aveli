# BCP-011

- TASK_ID: `BCP-011`
- TYPE: `GATE`
- TITLE: `Lock the membership app-entry boundary before baseline work starts`
- PROBLEM_STATEMENT: `Baseline and runtime work cannot proceed safely until the resolved app-entry boundary proves that memberships own app entry and that no onboarding, enrollment, or subject fallback survives in scope.`
- IMPLEMENTATION_SURFACES:
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-010_resolve_minimal_app_memberships_shape.md`
  - `actual_truth/contracts/onboarding_teacher_rights_contract.md`
  - `backend/app/repositories/memberships.py`
  - `backend/app/services/onboarding_state.py`
- TARGET_STATE:
  - the resolved app-entry contract is deterministic and blocking-ready
  - membership states that grant or deny app entry are explicit
  - onboarding and learner-content state cannot act as app-entry substitutes
  - downstream baseline tasks can depend on one membership boundary only
- DEPENDS_ON:
  - `BCP-010`
- VERIFICATION_METHOD:
  - assert one authority owner for app entry
  - assert no dependency on onboarding, `course_enrollments`, or role fields remains in the contract boundary
  - stop if any required membership field or state is still ambiguous

## GATE ASSERTIONS

- `app.memberships` is the sole canonical app-entry authority owner for the locked boundary.
- App-entry grant state is fully determined only by:
  - `status IN ('active', 'trialing')`
  - `end_date IS NULL OR end_date > now()`
- No onboarding field may grant app entry:
  - `onboarding_state`
  - `role_v2`
  - `role`
  - `is_admin`
- No learner-content field or table may grant app entry:
  - `course_enrollments`
  - `current_unlock_position`
  - lesson-content access state
- No billing or compatibility field may grant app entry:
  - `plan_interval`
  - `price_id`
  - `stripe_customer_id`
  - `stripe_subscription_id`
  - `subscription`

## GATE EVIDENCE

- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-010_resolve_minimal_app_memberships_shape.md`
  - already locks `app.memberships` as the sole app-entry owner
  - already excludes onboarding, auth-subject, learner-content, and legacy subscription drift from app-entry authority
- `actual_truth/contracts/onboarding_teacher_rights_contract.md`
  - explicitly states that `onboarding_state` does not replace membership authority for app entry
  - keeps `role_v2`, `role`, and `is_admin` in auth-subject authority rather than membership authority
- `Aveli_System_Decisions.md`
  - fixes `memberships` as app-access authority
  - fixes `course_enrollments` as the only canonical learner-content authority
- `aveli_system_manifest.json`
  - `membership_required_for_app_entry = true`
  - `membership_alone_never_grants_canonical_protected_course_content_access = true`
- `backend/app/services/onboarding_state.py`
  - derives onboarding state from membership and profile truth
  - does not define any path that turns onboarding state into app-entry authority
- `backend/app/routes/api_auth.py` and `backend/app/routes/api_profiles.py`
  - compute `membership_active` from `app.memberships` state and `end_date`
  - attach onboarding state separately, proving onboarding is adjacent output and not the authority owner
- `backend/app/repositories/memberships.py`
  - `get_membership()` reads `app.memberships` directly
  - legacy `get_latest_subscription()` helper still exists, but no current app-entry read in mounted runtime uses it

## GATE DECISION

- The resolved membership boundary is deterministic enough for append-only baseline work to proceed.
- No required membership field or grant/deny state remains ambiguous after source review.
- Onboarding, subject, and learner-content authorities are materially excluded from the locked app-entry boundary.
- Legacy subscription drift remains a runtime-cleanup risk only and does not invalidate this gate because it is not the locked app-entry authority path in current scope.

## EXECUTION LOCK

- EXPECTED_GATE_STATE:
  - one blocking-ready app-entry contract exists through `app.memberships`
  - downstream baseline work may rely on one owner and one grant/deny boundary only
- ACTUAL_GATE_STATE_BEFORE_ACTION:
  - `BCP-010` had resolved the owner and exclusion set, but this gate artifact had not yet certified that the boundary was safe for downstream baseline implementation
  - mounted runtime still contained adjacent onboarding derivation and a legacy subscription helper, which required explicit scope judgment before implementation could continue
- DECISION:
  - gate passes
- REMAINING_RISKS:
  - mounted runtime still carries legacy helper drift that must be removed or bypassed by later alignment work
  - baseline ownership for `app.memberships` still does not exist until `BCP-012`
- LOCK_STATUS:
  - `PASSED_FOR_BCP-012`
