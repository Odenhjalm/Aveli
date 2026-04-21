# SOI-001 BACKEND DOMAIN REPOSITORY FOUNDATION

- TASK_ID: `SOI-001`
- TYPE: `OWNER`
- GROUP: `BACKEND DOMAIN IMPLEMENTATION`

## Purpose

Create the canonical backend persistence layer for `app.special_offers` and
`app.special_offer_courses` so create and update flows can operate on special
offer state without borrowing bundle, commerce, or media authority.

## Contract References

- `actual_truth/contracts/special_offer_domain_contract.md`
- `actual_truth/contracts/special_offer_execution_contract.md`
- `actual_truth/contracts/course_monetization_contract.md`
- `actual_truth/contracts/commerce_membership_contract.md`
- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`

## DEPENDS_ON

- `[]`

## Dependency Requirements

- write only `app.special_offers` and `app.special_offer_courses` as special
  offer state
- preserve backend ownership of teacher binding, selected courses, and price
- keep bundle, checkout, Stripe, order, payment, and entitlement tables out of
  special-offer persistence

## Exact Scope

- repository read and write for special-offer root state
- repository read and write for ordered selected-course membership
- repository queries for teacher-scoped offer lookup
- repository read support for execution-visible state without side effects

## Verification Criteria

- create and update flows persist selected courses only in
  `app.special_offer_courses`
- repository reads order selected courses explicitly by `position`
- repository writes do not reuse `app.course_bundles` or
  `app.course_bundle_courses`
- repository layer does not write `app.media_assets`, `app.orders`,
  `app.payments`, or `app.memberships` as special-offer truth

## GO Condition

Go when a backend caller can persist a teacher-owned special offer with ordered
courses and price truth using only the accepted special-offer tables.

## BLOCKED Condition

Stop if any persistence layer treats bundle tables, course cover output
pointers, or frontend form state as canonical special-offer truth.

## Out Of Scope

- image generation
- output binding
- runtime read projection
- frontend UI
