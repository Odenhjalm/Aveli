# COURSE ACCESS CONTRACT

## STATUS

ACTIVE

This contract defines the canonical protected course-access truth.
This contract operates under `SYSTEM_LAWS.md` and `commerce_membership_contract.md`.

## 1. CONTRACT LAW

- Protected course-access authority is owned only by `app.course_enrollments`.
- `app.course_enrollments` owns protected course-access state only.
- `app.course_enrollments` does not own purchase truth.
- Membership alone never grants canonical protected course content.
- Course enrollment never grants app entry.

## 2. AUTHORITY MODEL

- `app.course_enrollments` is the only canonical protected course-access source entity.
- A course enrollment row is not proof of purchase without an order/payment trail.
- Canonical paid purchase authority remains outside this contract and is owned by `commerce_membership_contract.md`.
- Public course and lesson read semantics remain outside this contract and are owned by `course_public_surface_contract.md`.

## 3. PURCHASE DEPENDENCY

Canonical paid course purchase depends on the commerce contract:

- initiation: `POST /api/checkout/create`
- payment confirmation: `POST /api/stripe/webhook`

When a paid course purchase completes:

- webhook records payment under `commerce_membership_contract.md`
- webhook creates `app.course_enrollments` with `source = purchase`

No purchase flow may bypass that order/payment trail and create course access as fallback authority.

## 4. PROTECTED COURSE-ACCESS LAW

- Protected course content access requires canonical course-access state in `app.course_enrollments`.
- Membership state does not replace `app.course_enrollments` as protected course-access authority.
- Purchase authority does not replace `app.course_enrollments` as protected course-access state.
- Course-access state must remain explicit and non-implicit.
- Course access classification is owned by `app.courses.required_enrollment_source`.
- Valid course enrollment sources are `purchase` and `intro`.
- `intro` is the dedicated canonical source for introduction-course enrollments.
- A course enrollment grants protected course access when
  `app.course_enrollments.source` matches
  `app.courses.required_enrollment_source`.
- A backend-validated purchase or package entitlement MAY grant protected course
  access as an explicit purchase-entitlement override only when backend access
  state in `app.course_enrollments` proves the entitlement. This override MUST
  use purchase-source access state, MUST NOT create a fake `intro` enrollment,
  and MUST NOT be inferred from frontend, Stripe runtime, checkout return
  state, or payment state alone.
- If `app.courses.required_enrollment_source` is `null`, protected course access fails closed.
- `sellable`, `price_amount_cents`, `group_position`, Stripe state, order state, payment state, and frontend state MUST NOT classify protected course access.
- `/courses/{course_id}/access` MUST expose backend-authored `can_access`.
- `/courses/{course_id}/access` MUST expose backend-authored `next_unlock_at` as a learner-safe derived timestamp or `null`.
- `next_unlock_at` must be computed only from canonical backend scheduling authority and MUST NOT expose custom-drip rows, offsets, mode flags, or any frontend-reconstructed schedule.
- Frontend course gates MUST use backend-authored `can_access` and MUST NOT infer protected course access from enrollment presence, checkout success, order state, payment state, or Stripe state.
- Frontend learner timing UX MUST use backend-authored `next_unlock_at` and MUST NOT reconstruct drip timing from legacy intervals, custom rows, or authored schedule structures.
- Frontend MUST NOT compare lesson positions to compute locked/unlocked,
  current, upcoming, completed, previous, or next lesson state.

## 5. FORBIDDEN PATTERNS

- Membership as protected course-access authority.
- Course enrollment as standalone purchase authority.
- Protected course access without canonical course-enrollment state.
- Fallback protected access derived from membership state alone.
- Fallback protected access derived from order/payment state without course-enrollment state.
- Intro course enrollment using `purchase`, `referral`, `coupon`, or any source other than `intro`.
- Fake intro enrollment created from purchase or package entitlement.
- Frontend-authored CTA, price, intro restriction, or lesson-lock decisions.

## 6. INTRO ACCESS LAW

- Introduction courses use `app.courses.required_enrollment_source = intro`.
- Introduction course protected access requires `app.course_enrollments.source = intro`.
- Introduction course selection and enrollment use only source `intro`.
- If a user is already in an active intro drip state in another intro course,
  a new intro-course enrollment CTA MUST be backend-authored as `blocked`.
- A valid purchase or package entitlement may grant access and produce a
  backend-authored `continue` CTA, but it MUST NOT create or masquerade as an
  intro enrollment and MUST NOT satisfy intro-selection progression.
- Publish-time workflows may use `app.courses.group_position` only as
  structural/defaulting input before persisting
  `app.courses.required_enrollment_source`; runtime protected access checks use
  persisted backend-owned access state.

## 6A. COURSE ENTRY CTA AND PROGRESSION PROJECTION LAW

`GET /courses/{course_id_or_slug}/entry-view` is the canonical backend Course
Entry/Gateway read surface for learner course-entry decisions.

The backend owns the CTA decision. Allowed CTA types are:

- `enroll`
- `buy`
- `continue`
- `blocked`
- `unavailable`

Every CTA object MUST include:

- `type`
- `label`
- `enabled`
- `reason_code`
- `reason_text`
- `price` when relevant
- `action` when relevant

CTA rules:

- intro courses show an enrollment CTA only when backend selection state allows
  creating a new intro enrollment
- intro courses with another active intro drip state return `blocked`
- valid purchase/package entitlement returns `continue` when access is granted
- premium courses return `buy` only from backend-owned purchasability and price
  state
- already enrolled users return `continue` with a backend-authored action
  target
- ambiguous or incomplete authority returns `unavailable`

The backend owns lesson progression projection for Course Entry/Gateway.
Per-lesson projection MUST include:

- locked/unlocked availability
- current/upcoming/completed state
- `next_unlock_at`
- previous/next navigation state
- locked reason

Frontend MUST render the projection only. Frontend MUST NOT infer lesson
availability from `position`, `current_unlock_position`, local enrollment
presence, checkout return state, Stripe state, or route state.

## 6B. LESSON VIEW ACCESS AND CTA PROJECTION LAW

`GET /courses/lessons/{lesson_id}` is the canonical `lesson_view_surface`
defined by `course_public_surface_contract.md`.

`lesson_view_surface` MAY project access, CTA, pricing eligibility, progression,
and navigation decisions, but it MUST NOT become a separate access or CTA
authority. The owning backend access/CTA projection service is shared with
Course Entry/Gateway.

The `lesson_view_surface.access` projection MUST include:

- `has_access`
- `is_enrolled`
- `is_in_drip`
- `is_premium`
- `can_enroll`
- `can_purchase`

Access projection rules:

- `has_access` is backend-authored request authorization for the selected
  lesson runtime view.
- learner-mode `has_access` requires canonical course-access state and valid
  lesson unlock state.
- `is_enrolled` is true only from canonical `app.course_enrollments` state.
- `is_in_drip` is true only when backend-owned drip/progression state blocks
  the selected lesson or blocks a new intro-course enrollment CTA.
- `is_premium` is derived only from
  `app.courses.required_enrollment_source = purchase`.
- `can_enroll` is derived only from backend selection/enrollment eligibility.
- `can_purchase` is derived only from backend monetization and purchasability
  projection.

CTA projection rules:

- CTA is derived only from backend access and monetization projection.
- Lesson View CTA types use the same enum as Course Entry/Gateway:
  `enroll`, `buy`, `continue`, `blocked`, `unavailable`.
- The frontend MUST NOT choose CTA type, label, enabled state, reason, action,
  enrollment eligibility, purchase eligibility, or lock state.

Preview rule:

- `GET /courses/lessons/{lesson_id}?preview=true` may authorize persisted
  lesson rendering through teacher/studio authorization instead of learner
  enrollment.
- preview authorization MUST NOT create, mutate, imply, or masquerade as learner
  `app.course_enrollments` access.
- preview mode MUST use the same response shape and backend projections as
  learner Lesson View.

## 7. IMPLEMENTATION DRIFT OUTSIDE CONTRACT

- Current webhook implementation does not yet fully align purchase settlement with canonical course-access creation in all branches.
- Current repo code may still mix purchase and access reasoning in the same runtime paths.

## 8. ACCESS REVOCATION LAW

- Canonical one-off digital product access revocation is owned only by backend mutation of `app.course_enrollments`.
- A valid withdrawal outcome for a paid course or paid bundle within the legally applicable withdrawal window MUST revoke the resulting protected course access immediately.
- A separate defect, dispute, chargeback, fraud, delivery-failure, or statutory remedy outcome MAY also revoke protected course access, but only through canonical backend-owned access mutation.
- After the legally applicable withdrawal window, change of mind alone MUST NOT revoke protected course access.
- Stripe refund state, Stripe cancellation state, Stripe dispute state, frontend state, token claims, and ad hoc support surfaces are not protected course-access authority and are not protected course-access revocation authority.
- Orders and payments remain purchase substrate, but they do not revoke access by themselves without backend-owned course-access mutation.
- Membership cancellation, membership withdrawal, or membership refund does not rewrite protected course access unless backend separately resolves a one-off product remedy path that canonically mutates `app.course_enrollments`.

## 9. FINAL ASSERTION

- This contract is the canonical protected course-access truth.
- It is lockable as a contract artifact.
- Contract truth and implementation drift are intentionally separated.
