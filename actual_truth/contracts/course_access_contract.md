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
- A course enrollment grants protected course access only when `app.course_enrollments.source` matches `app.courses.required_enrollment_source`.
- If `app.courses.required_enrollment_source` is `null`, protected course access fails closed.
- `sellable`, `price_amount_cents`, `group_position`, Stripe state, order state, payment state, and frontend state MUST NOT classify protected course access.
- `/courses/{course_id}/access` MUST expose backend-authored `can_access`.
- `/courses/{course_id}/access` MUST expose backend-authored `next_unlock_at` as a learner-safe derived timestamp or `null`.
- `next_unlock_at` must be computed only from canonical backend scheduling authority and MUST NOT expose custom-drip rows, offsets, mode flags, or any frontend-reconstructed schedule.
- Frontend course gates MUST use backend-authored `can_access` and MUST NOT infer protected course access from enrollment presence, checkout success, order state, payment state, or Stripe state.
- Frontend learner timing UX MUST use backend-authored `next_unlock_at` and MUST NOT reconstruct drip timing from legacy intervals, custom rows, or authored schedule structures.

## 5. FORBIDDEN PATTERNS

- Membership as protected course-access authority.
- Course enrollment as standalone purchase authority.
- Protected course access without canonical course-enrollment state.
- Fallback protected access derived from membership state alone.
- Fallback protected access derived from order/payment state without course-enrollment state.

## 6. IMPLEMENTATION DRIFT OUTSIDE CONTRACT

- Current webhook implementation does not yet fully align purchase settlement with canonical course-access creation in all branches.
- Current repo code may still mix purchase and access reasoning in the same runtime paths.

## 7. ACCESS REVOCATION LAW

- Canonical one-off digital product access revocation is owned only by backend mutation of `app.course_enrollments`.
- A valid withdrawal outcome for a paid course or paid bundle within the legally applicable withdrawal window MUST revoke the resulting protected course access immediately.
- A separate defect, dispute, chargeback, fraud, delivery-failure, or statutory remedy outcome MAY also revoke protected course access, but only through canonical backend-owned access mutation.
- After the legally applicable withdrawal window, change of mind alone MUST NOT revoke protected course access.
- Stripe refund state, Stripe cancellation state, Stripe dispute state, frontend state, token claims, and ad hoc support surfaces are not protected course-access authority and are not protected course-access revocation authority.
- Orders and payments remain purchase substrate, but they do not revoke access by themselves without backend-owned course-access mutation.
- Membership cancellation, membership withdrawal, or membership refund does not rewrite protected course access unless backend separately resolves a one-off product remedy path that canonically mutates `app.course_enrollments`.

## 8. FINAL ASSERTION

- This contract is the canonical protected course-access truth.
- It is lockable as a contract artifact.
- Contract truth and implementation drift are intentionally separated.
