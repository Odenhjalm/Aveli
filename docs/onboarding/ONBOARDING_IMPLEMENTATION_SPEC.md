> This document is the implementation-facing companion to the Aveli Onboarding Contract Spec.
> It defines the required system changes needed to make onboarding deterministic, backend-authoritative,
> refresh-safe, billing-aligned, and launch-ready.
>
> This is a no-code planning document. It does not authorize implementation drift from the contract.

# Aveli Onboarding Implementation Spec

**Version:** 1.0
**Status:** Decision-ready, implementation-facing
**Depends on:** `docs/onboarding/ONBOARDING_CONTRACT_SPEC.md`

---

## Purpose

This document translates the onboarding contract into the system shape that implementation must follow.

It defines:

- required backend behavior
- required frontend behavior
- required data-model changes
- required Stripe flow consolidation
- required email-flow behavior
- required migration strategy
- required regression coverage

## Canonical System Shape

The implementation is organized into five domains:

- `auth`
  Account creation, login, session hydration, email verification truth.

- `billing`
  Canonical checkout creation, membership activation truth, webhook reconciliation, billing portal.

- `profile`
  Explicit profile save and explicit profile completeness evaluation.

- `onboarding`
  Canonical state derivation, allowed transitions, final completion gate, next-step computation.

- `course-selection`
  Intro course listing, durable intro course selection, selected-course truth.

No other domain may silently advance onboarding progression.

## Required Data Model

Implementation uses durable onboarding milestones instead of heuristics.

- `app.user_onboarding`
  Columns:
  - `user_id`
  - `selected_intro_course_id`
  - `profile_completed_at`
  - `onboarding_completed_at`
  - timestamps

- Canonical onboarding states
  - `registered_unverified`
  - `verified_unpaid`
  - `paid_profile_incomplete`
  - `paid_profile_complete_intro_unselected`
  - `paid_profile_complete_intro_selected`
  - `onboarding_complete`

- Profile completeness
  - Required fields are `display_name`, `bio`, and avatar.
  - `avatar_media_id` is the primary runtime truth.
  - Legacy `photo_url` may be used only for conservative backfill.

## Backend Authority

Backend owns one onboarding service and one canonical payload:

- `GET /api/onboarding/me`
- `GET /api/onboarding/intro-courses`
- `POST /api/onboarding/select-intro-course`
- `POST /api/onboarding/complete`

The onboarding payload includes:

- `onboarding_state`
- `next_step`
- `email_verified`
- `membership_active`
- `profile_complete`
- `intro_course_selected`
- `onboarding_complete`
- `missing_profile_fields`
- `selected_intro_course_id`
- `billing_pending`

Read paths remain pure reads:

- `/auth/me`
- `/profiles/me`
- `/api/me/membership`
- `/api/me/entitlements`
- bootstrap and hydration flows

Write paths may trigger reevaluation only through explicit mutations:

- register
- verify email
- membership activation reconciliation
- profile save
- avatar upload
- intro selection
- final completion

## Billing Contract

Membership onboarding uses one canonical checkout creator:

- `POST /api/billing/create-subscription`

Rules:

- `30` day trial
- unified success URL
- unified cancel URL
- unified billing portal return
- webhook-first membership activation
- `GET /api/billing/session-status` only as polling fallback

Legacy subscription use of `POST /api/checkout/create` is non-canonical and rejected for onboarding.

## Frontend Routing Contract

Frontend routing is driven by the canonical onboarding payload rather than ad hoc auth/profile/billing guesses.

Required onboarding routes:

- `/resume-onboarding`
- `/verify`
- `/subscribe`
- `/create-profile`
- `/select-intro-course`
- `/welcome`
- authenticated home

Required properties:

- refresh-safe
- deep-link-safe
- external checkout return-safe
- deterministic after login

No onboarding-critical route may depend on transient `state.extra` to survive refresh.

## UX and Email Contract

Onboarding-critical copy must clearly explain:

- `30 dagars trial`
- `en lektion per vecka`
- `fyra lektioner per introduktionskurs`
- what happens after verify
- what happens after checkout
- what happens after profile completion
- what onboarding completion means

Verification and reset emails must state:

- link expiry
- what to do if the link fails
- how to get support

## Migration Strategy

Before launch, existing users must be reclassified conservatively.

- Backfill `profile_completed_at` when current profile already satisfies the required profile fields.
- Backfill `selected_intro_course_id` only when historical intro selection is unambiguous.
- Do not backfill `onboarding_completed_at` without deterministic legacy proof.
- Prefer the highest non-terminal state when history is ambiguous.

## Regression Coverage

Backend regression coverage includes:

- all canonical onboarding states
- verify-email idempotency
- membership activation transitions
- profile completion rules
- durable intro selection
- guarded final completion
- read endpoints that do not mutate onboarding

Frontend regression coverage includes:

- redirect to the correct route for each onboarding state
- refresh safety on onboarding routes
- deep-link correction when a user opens a later step too early
- verify-without-session continuation
- delayed webhook handling on checkout success

Integration coverage includes:

- register -> verify -> subscribe -> success -> create profile -> select intro -> welcome -> home
- external browser checkout return
- delayed webhook after payment
- referral onboarding
- impossible completion without explicit intro selection and guarded final completion

## Implementation Sequence

1. Canonical model
2. Backend authority
3. Billing consolidation
4. Frontend routing
5. Copy and email
6. Migration and regression
