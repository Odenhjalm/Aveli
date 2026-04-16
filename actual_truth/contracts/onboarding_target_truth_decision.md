# Onboarding Target Truth Decision

## STATUS

DRAFT
NO-CODE TARGET-TRUTH DECISION CAPTURE

## PURPOSE

This document exists to make onboarding target truth explicit before any
application-domain-map drafting begins.

This document separates:
- verified current truth
- locked target truth
- explicit out-of-scope items

This document does not claim that locked target truth is already implemented in
repo current state.

## VERIFIED CURRENT TRUTH

- [contract truth] `auth.users` is current contract and boundary truth for authentication identity only.
- [mixed truth] Current contract truth, baseline shape, and runtime reads place `onboarding_state`, `role_v2`, `role`, and `is_admin` on `app.auth_subjects`.
- [mixed truth] `POST /auth/onboarding/complete` is the current contract-defined onboarding-completion authority, and the mounted runtime route writes `app.auth_subjects.onboarding_state = 'completed'`.
- [mixed truth] `/profiles/me` is the current contract-defined projection-only surface, and the mounted runtime write surface limits updates to `display_name` and `bio`.
- [mixed truth] `app.memberships` is current contract-plus-baseline truth for global app-membership current state and current input to entry composition.
- [contract truth] `app.orders` and `app.payments` are current purchase/payment truth in active commerce contracts.
- [contract truth] `app.course_enrollments` is current contract truth for protected course access.
- [runtime truth] `GET /entry-state` currently computes post-auth routing outputs from `onboarding_state` and current membership state.
- [runtime drift] Current runtime also contains separate backend entry evaluation and guard enforcement outside `GET /entry-state`, including `evaluate_app_entry`, `require_app_entry`, and `AppEntryUser`.
- [mixed truth] Current referral runtime is separate from invite-token auth flow: it uses email delivery, post-auth `/referrals/redeem`, and membership handoff into `app.memberships`.
- [mixed truth] Current referral-derived membership handoff uses the non-purchase source bucket `invite`, and baseline constraints require `source = 'invite'` grants to be time-bounded.
- [runtime truth] Current referral email transport does not bring the user into onboarding create-profile; the runtime signup URL resolves to `/login`.
- [runtime drift] Current runtime blocks onboarding completion when current-user `display_name` is absent; this is profile-derived onboarding drift, not separate onboarding authority.

## LOCKED TARGET TRUTH

- `auth.users = authentication identity only`.
- `app.auth_subjects = canonical application subject authority`.
- More specifically, `app.auth_subjects` is the canonical application subject
  authority for:
  - onboarding subject state
  - app-level role subject fields
  - app-level admin subject fields
- Onboarding state belongs only to `app.auth_subjects`.
- `/profiles/me = projection only`.
- `app.memberships = sole current-state authority for global app membership`.
- `app.orders` and `app.payments = purchase/payment truth only`.
- `app.course_enrollments = protected course access truth only`.
- `GET /entry-state` owns the canonical post-auth decision model.
- `GET /entry-state` is the sole authority for post-auth routing outputs.
- Backend guards may enforce the canonical entry model technically, but they
  must not define, derive, extend, or invent a separate app-entry model.
- Referral must converge into one canonical grant path into `app.memberships`.
- Referral grants time-bounded global paid-access-equivalent membership state in
  `app.memberships`.
- Referral does not create purchase truth.
- Referral does not create payment truth.
- Referral occurs via email link.
- The referral email link must bring the user into onboarding at the
  create-profile step.
- Create-profile is an onboarding step, not profile-projection authority.
- At create-profile, the user must provide name and may optionally add image and
  bio.
- The old ordinary self-signup target flow
  `register -> subscribe -> create-profile -> app` is superseded.
- The new locked ordinary self-signup target flow is:
  `register -> checkout -> create-profile -> welcome -> onboarding-complete -> app`.
- Ordinary self-signup checkout is required before create-profile.
- Ordinary self-signup checkout creates purchase-backed membership state with a
  30-day free trial and required card details.
- Checkout remains purchase/payment authority only and does not own onboarding
  completion.
- Welcome is an onboarding-owned step.
- Successful create-profile moves onboarding state to `welcome_pending`.
- Onboarding completes only after explicit welcome confirmation:
  `Jag förstår hur Aveli fungerar`.
- Referral must not create a separate onboarding authority.
- Referral must not create a separate onboarding state machine.
- Referral remains coherent by keeping the create-profile exception before
  payment routing and by continuing through the shared welcome completion gate
  before app entry.
- Invite must be removed.

## EXPLICIT OUT-OF-SCOPE ITEMS

- Broader commerce redesign is out of scope.
- Stripe transport and webhook implementation detail is out of scope.
- Admin and teacher-rights doctrine is out of scope.
- Media-pipeline implementation detail is out of scope except that locked target
  truth allows optional image input during create-profile.
- This document does not rewrite current contracts by itself.
- This document does not merge current truth and target truth into one
  statement.

## CONTRADICTIONS BETWEEN CURRENT REPO TRUTH AND LOCKED TARGET TRUTH

- Current contracts do not yet explicitly name `app.auth_subjects` as the
  canonical application subject authority; they currently name field ownership.
- Current runtime contains backend entry guards outside `GET /entry-state`,
  which conflicts with the locked target that `GET /entry-state` is the sole
  authority for post-auth routing outputs.
- Current runtime uses separate backend entry evaluation in `require_app_entry`,
  which conflicts with the locked target that guards may enforce but must not
  define a separate app-entry model.
- Current runtime referral link goes to login, not to onboarding
  create-profile.
- Current runtime and current auth contract require `display_name` during
  registration, which conflicts with locked target placement of required name at
  create-profile.
- Current runtime ties onboarding completion to profile-name presence, which
  conflicts with the locked target that create-profile is an onboarding step and
  that onboarding authority remains on `app.auth_subjects`.
- Current repo still carries invite semantics in active auth and membership
  flows, which conflicts with the locked target that invite must be removed.
- Current referral membership handoff still uses source bucket `invite`, which
  conflicts with the locked target only to the extent that invite removal
  requires a replacement canonical non-purchase membership path; that exact
  replacement label is not defined in this decision document.
- Current `/profiles/me` surface exists correctly as projection, but repo
  current state does not yet express create-profile as a distinct onboarding
  step separate from profile-projection authority.

## FINAL ASSERTION

- Verified current truth and locked target truth are intentionally separate in
  this document.
- Locked target truth is explicit, target-only, and not asserted as already true
  in repo current state.
- This decision document preserves the authority separation between:
  - identity
  - application subject state
  - onboarding completion
  - profile projection
  - membership current state
  - purchase/payment truth
  - protected course access
  - post-auth routing outputs
- If any later draft would blur those authority boundaries, that draft must fail
  closed.

Verification:
- All user-facing text is in Swedish: not confirmed. For example, [studio.py](C:/Users/aveli/Aveli/backend/app/routes/studio.py):721 emits `"Failed to send referral invitation email"`, and [app_failure.dart](C:/Users/aveli/Aveli/frontend/lib/core/errors/app_failure.dart):229 can return raw detail text unchanged.
- Prompts are copy-pasteable and in English: not confirmed. [task.fix.md](C:/Users/aveli/Aveli/codex/prompts/task.fix.md):1 and [task.feature.md](C:/Users/aveli/Aveli/codex/prompts/task.feature.md):1 remain mixed-language.
