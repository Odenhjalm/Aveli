
# Aveli Onboarding Contract Spec

**Version:** 1.0
**Status:** Decision-ready
**Scope:** Signup, email verification, membership checkout, profile creation, intro course selection, onboarding completion, email service messaging, routing/refresh continuity

---

## 1. Purpose

This document defines the canonical onboarding contract for Aveli.

The purpose is to ensure that onboarding is:

* sequential
* deterministic
* refresh-safe
* resistant to bypass
* aligned across backend, frontend, email, and Stripe
* clear to the future student at every step

This contract replaces any implicit, split, or heuristic onboarding behavior.

---

## 2. Product Goal

A new student must move through a single clear path:

1. create account
2. verify email
3. activate membership through checkout
4. create profile
5. choose one introduction course
6. enter the product with onboarding complete

The experience must make it clear that:

* the student receives **one lesson per week**
* each **introduction course contains four lessons**
* membership is the gateway into the student experience
* onboarding is not complete until all required milestones are truly satisfied

---

## 3. Canonical Principles

### 3.1 Single source of truth

All onboarding progression is determined by backend-owned state.

Frontend must never invent onboarding completion or infer milestone completion from loose heuristics alone.

### 3.2 Explicit milestones

Every onboarding step must correspond to a durable, inspectable milestone.

### 3.3 No read-path mutation

No GET/read/bootstrap/profile-fetch route may mutate onboarding state.

Onboarding state may only change at explicit mutation boundaries.

### 3.4 Deterministic continuation

A user must always land in the correct next step after:

* refresh
* deep link
* external browser checkout return
* delayed webhook
* email verification on another device
* temporary loss of local session

### 3.5 Completion is server-validated

Onboarding complete may only be reached when all required prerequisites are satisfied and verified by backend.

---

## 4. Required Onboarding Milestones

The following milestones are required before onboarding is considered complete.

### M1. Account created

The user account exists.

### M2. Email verified

The user has verified their email address.

### M3. Membership active

The user has an active eligible membership.

### M4. Profile completed

The user has completed the required profile fields.

### M5. Introduction course selected

The user has explicitly selected one introduction course.

### M6. Onboarding completed

The system marks onboarding complete only after M1-M5 are satisfied.

---

## 5. Canonical Onboarding State Machine

The canonical onboarding states are:

### S0. `registered_unverified`

Meaning:

* account exists
* email not verified

Required truth:

* user exists
* email_verified = false

Next allowed transition:

* `verified_unpaid`

---

### S1. `verified_unpaid`

Meaning:

* email verified
* no active membership yet

Required truth:

* email_verified = true
* membership_active = false

Next allowed transition:

* `paid_profile_incomplete`

---

### S2. `paid_profile_incomplete`

Meaning:

* email verified
* active membership exists
* required profile not yet complete

Required truth:

* email_verified = true
* membership_active = true
* profile_complete = false

Next allowed transition:

* `paid_profile_complete_intro_unselected`

---

### S3. `paid_profile_complete_intro_unselected`

Meaning:

* email verified
* active membership exists
* profile complete
* intro course not yet selected

Required truth:

* email_verified = true
* membership_active = true
* profile_complete = true
* intro_course_selected = false

Next allowed transition:

* `paid_profile_complete_intro_selected`

---

### S4. `paid_profile_complete_intro_selected`

Meaning:

* all real onboarding prerequisites are satisfied
* onboarding finalization screen may be shown

Required truth:

* email_verified = true
* membership_active = true
* profile_complete = true
* intro_course_selected = true

Next allowed transition:

* `onboarding_complete`

---

### S5. `onboarding_complete`

Meaning:

* user has completed the onboarding journey
* app may route user to normal authenticated home

Required truth:

* all prior milestones true
* backend-confirmed final completion marker recorded

This is terminal for onboarding.

---

## 6. Disallowed State Behavior

The following are explicitly forbidden:

* setting onboarding complete from the client without backend prerequisite validation
* using profile `updated_at > created_at` alone as the sole truth for profile completion
* mutating onboarding state inside `/auth/me`, `/profiles/me`, or any other read route
* treating “payment initiated” as “membership active”
* treating email verification success as sufficient for onboarding completion
* treating intro course exposure or first visible intro course as equivalent to intro course selection

---

## 7. Canonical Milestone Ownership

### 7.1 Account created

**Owner:** backend auth creation flow
**Truth location:** account/auth user + canonical user profile row
**Frontend role:** display/routing only

### 7.2 Email verified

**Owner:** backend verification flow
**Truth location:** canonical verified-email field derived from auth provider truth
**Frontend role:** display/routing only

### 7.3 Membership active

**Owner:** backend membership domain
**Truth location:** canonical membership record, based on webhook-confirmed billing truth
**Frontend role:** display/routing only

### 7.4 Profile completed

**Owner:** backend profile domain
**Truth location:** explicit profile completeness evaluation against required fields
**Frontend role:** submit form and render completeness state

### 7.5 Intro course selected

**Owner:** backend onboarding/course selection domain
**Truth location:** durable persisted selected intro course record or field
**Frontend role:** submit selection and render current choice

### 7.6 Onboarding complete

**Owner:** backend onboarding domain
**Truth location:** guarded completion transition after all prerequisites validated
**Frontend role:** trigger final acknowledgment only if backend allows it

---

## 8. Canonical Write Points

Only the following actions may advance onboarding state.

### W1. Register

Creates account and initializes onboarding state to `registered_unverified`.

### W2. Verify email

Marks email as verified and advances state to `verified_unpaid` if membership is not active.

### W3. Membership activation

Occurs only when backend has durable billing truth that membership is active.
This advances state:

* from `verified_unpaid` to `paid_profile_incomplete`
* or to the appropriate later state if profile/intro milestones are already satisfied

### W4. Profile save

When required fields are satisfied, advances state:

* from `paid_profile_incomplete` to `paid_profile_complete_intro_unselected`

### W5. Intro course selection

When a valid intro course is explicitly selected, advances state:

* from `paid_profile_complete_intro_unselected` to `paid_profile_complete_intro_selected`

### W6. Final onboarding completion

A guarded backend mutation may advance:

* from `paid_profile_complete_intro_selected` to `onboarding_complete`

This write point must verify all prerequisites at execution time.

---

## 9. Read Behavior Contract

The following routes may read onboarding state but may not mutate it:

* auth bootstrap
* auth me
* profile me
* membership me
* entitlements me
* route guards
* app startup hydration

Any sync logic must be removed from read paths and moved into explicit write boundaries or derived read-only computation.

---

## 10. Canonical Routing Contract

Frontend routing must be driven by backend onboarding state.

### Route target by state

* `registered_unverified` → `/verify`
* `verified_unpaid` → `/subscribe`
* `paid_profile_incomplete` → `/create-profile`
* `paid_profile_complete_intro_unselected` → `/select-intro-course`
* `paid_profile_complete_intro_selected` → `/welcome`
* `onboarding_complete` → authenticated home

### Routing rule

If an authenticated user attempts to access a later step than their current allowed state, frontend must redirect them to the canonical next step.

### Refresh rule

Refreshing any onboarding page must return the user to the correct next step based on backend truth.

### Deep-link rule

Deep-linking to `/success`, `/welcome`, `/create-profile`, or intro-course step must not allow skipping prerequisites.

---

## 11. Verification Flow Contract

### 11.1 Verification email purpose

The verification email exists to move the user from account creation into the paid membership step.

### 11.2 Verification outcome

When verification succeeds:

* if user session is valid, app routes directly to the canonical next step
* if no local session exists, the user must still be deterministically guided into re-authentication and then into the canonical next step

### 11.3 Required behavior for no-session verification

Verification success must not dead-end on a vague “log in to continue” page.

It must preserve onboarding intent and continue to:

* login
* session restoration
* immediate redirect to `/subscribe` if state is `verified_unpaid`

### 11.4 Verification messaging

The user must be clearly told:

* email is verified
* next step is membership activation
* what happens after membership activation

---

## 12. Membership / Stripe Contract

### 12.1 Canonical checkout creator

There must be exactly one canonical membership checkout creation path for the onboarding funnel.

All legacy or alternate creators must be retired or explicitly marked non-onboarding.

### 12.2 Canonical truth for active membership

Membership becomes active only from durable backend billing truth, normally webhook-confirmed.

Frontend redirect alone is not sufficient.

### 12.3 Canonical success and cancel URLs

There must be one success contract and one cancel contract used consistently across:

* backend config
* Stripe
* frontend route handling
* deep-link handling
* documentation

### 12.4 Checkout continuity

After successful payment:

* user must land on a deterministic success surface
* app must reconcile billing truth
* app must move user forward to profile creation when membership becomes active

### 12.5 Trial policy

The trial promise must be either:

* truly implemented in the canonical checkout creator, or
* removed from all product and marketing copy

No mismatch is allowed.

---

## 13. Profile Completion Contract

Profile completion must not be inferred from a timestamp-only heuristic.

A profile is complete only when all required profile fields are present and valid.

### Required profile fields

These should be finalized as product decisions, but must be explicit. Example:

* display name
* first name
* last name, if required
* any student-facing required preference or onboarding identity field
* any legally or operationally necessary field

Backend must expose:

* `profile_complete = true|false`
* optional reasons or missing fields list

---

## 14. Intro Course Selection Contract

Introduction course selection is part of onboarding.

### 14.1 Requirement

A student must explicitly choose one introduction course before onboarding can complete.

### 14.2 Truth

Selection must be durable and inspectable.

### 14.3 Allowed behavior

The system may recommend or pre-highlight a course, but onboarding does not treat recommendation as selection.

### 14.4 Disallowed behavior

Auto-loading the first available intro course is not equivalent to a user choice.

---

## 15. Welcome Step Contract

The welcome step is a final acknowledgment layer, not a logic shortcut.

### Allowed purpose

* confirm that setup is finished
* orient the student
* explain next learning cadence
* explain where to go next

### Disallowed purpose

* force onboarding complete without validating prerequisites
* act as a bypass to mark the user finished

---

## 16. Product Messaging Contract

The following messages must be consistently true everywhere they appear:

### 16.1 Weekly cadence

The student must be clearly told that they receive **one lesson per week**.

This message must appear in onboarding-visible surfaces, not only buried in marketing.

### 16.2 Intro course structure

The student must be clearly told that each introduction course contains **four lessons**.

This must appear before or during intro course selection.

### 16.3 Post-verification clarity

After email verification, the student must clearly understand:

* what just happened
* what the next step is
* why membership is the next step

### 16.4 Post-checkout clarity

After successful checkout, the student must clearly understand:

* payment is being confirmed
* next step is profile creation
* after profile creation they will choose an intro course

### 16.5 Completion clarity

Before entering the product, the student must understand:

* what they now have access to
* where their chosen intro course lives
* how the one-lesson-per-week structure works

---

## 17. Email Contract

### 17.1 Verification email

Must include:

* trusted sender identity
* clear subject
* concise explanation of why verification matters
* explicit next step after verification
* support fallback
* expiry clarity if applicable

### 17.2 Password reset email

Must include:

* explicit expiry
* support fallback
* concise action language

### 17.3 Invitation email

Must align with the same onboarding journey and language strategy as the app.

### 17.4 Delivery behavior

Missing production email configuration must not silently degrade in a way that pretends onboarding mail succeeded.

Production-critical environments must fail fast or expose visible operational health.

---

## 18. Referral Policy Contract

If referral membership can legitimately satisfy membership activation, that path must still respect the rest of onboarding:

* email verified
* profile completed
* intro course selected
* onboarding completed

Referral may skip paid checkout only if explicitly intended by product policy.

It may not skip the rest of onboarding milestones.

---

## 19. Legacy and Migration Contract

Historical states or backfills that collapsed users directly into terminal completion must not remain as unreviewed truth.

Before launch:

* legacy onboarding states must be audited
* migrated users must be reclassified against the new canonical milestones
* stale states that incorrectly imply completion must be corrected through a controlled migration plan

---

## 20. Launch Acceptance Criteria

The onboarding system is launch-ready only when all of the following are true:

### Functional

* every user is routed to exactly one canonical next step
* refresh on every onboarding screen is safe
* deep-linking cannot bypass prerequisites
* verification works with and without existing local session
* checkout return works from external browser and WebView flows
* active membership is backend-confirmed
* profile completion is explicit and durable
* intro course selection is explicit and durable
* onboarding complete cannot be set early

### Product

* trial promise matches real billing behavior
* intro-course promise matches real access rules
* weekly cadence is clearly communicated
* four-lesson intro structure is clearly communicated

### Operational

* email delivery configuration is explicit and trustworthy
* Stripe success/cancel contracts are singular and consistent
* old routes and legacy onboarding logic are retired or contained

---

## 21. Canonical Decision Summary

The following decisions are locked by this spec:

1. Onboarding completion requires:

   * verified email
   * active membership
   * completed profile
   * selected intro course

2. Intro course selection is a real onboarding milestone, not optional garnish.

3. Onboarding state is backend-owned and may only change at explicit mutation points.

4. Read routes may not mutate onboarding state.

5. There will be one canonical membership checkout path.

6. There will be one canonical success/cancel callback contract.

7. Trial and course-access copy must match real implementation exactly.

8. Welcome is the final acknowledgment step, not the place where prerequisites magically become true because the client pressed a button.

---

## 22. Implementation Guidance Boundary

This document does not define code-level implementation details.

It defines the contract that implementation must obey.

Any future frontend, backend, migration, Stripe, or email changes must be validated against this document.

---

