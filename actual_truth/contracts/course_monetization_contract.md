# COURSE MONETIZATION CONTRACT

## STATUS

ACTIVE

This contract defines the canonical commerce truth for course pricing, bundle pricing,
Stripe product/price mapping, teacher selling experience, and backend monetization
authority boundaries.
This contract operates under `SYSTEM_LAWS.md`,
`commerce_membership_contract.md`, and
`supabase_integration_boundary_contract.md`.

## 1. CONTRACT LAW

- Course purchase authority is owned only by `app.orders` and `app.payments`.
- Course access authority is owned only by `course_enrollments`.
- Monetization pricing authority is owned only by backend-mediated canonical state.
- Teacher pricing input is intent only until backend validates and persists it.
- Stripe is infrastructure for catalog/payment collection only.
- Stripe is NOT monetization authority.
- Frontend is NOT monetization authority.
- Teacher UI is NOT monetization authority.
- Course monetization and bundle monetization are separate from membership authority.
- Course monetization and bundle monetization are separate from future marketplace and payout authority.

## 2. COURSE MONETIZATION AUTHORITY

- A course becomes sellable only when backend confirms all required monetization state.
- A course MUST NOT become sellable from frontend form state alone.
- A course MUST NOT become sellable from Stripe dashboard/runtime state alone.
- Canonical course monetization state is backend-owned.
- A course is canonically sellable IF AND ONLY IF:
  - backend validates teacher ownership
  - backend validates pricing
  - backend validates Stripe mapping consistency
  - backend marks the course as sellable
- If any sellability requirement is missing or invalid, the course is not sellable.
- Backend is the only authority allowed to project sellability to frontend.

## 3. PRICING AUTHORITY

- A teacher MAY set course sale pricing intent only for courses the teacher canonically owns.
- Teacher pricing intent MUST be validated and persisted by backend before it becomes canonical.
- Frontend pricing state MUST NEVER define final price authority.
- Student-facing displayed price MUST be a backend-owned projection.
- Pricing for a completed purchase is immutable for that completed purchase.
- Later price changes apply only to future purchases.
- Admin MAY override teacher pricing only through explicit backend-admin action.
- Admin override is governance authority for future sales only.
- Admin override MUST NOT rewrite completed order or payment history.
- Teacher pricing without canonical course ownership is forbidden.

## 4. SELLABLE MODEL

- `course.sellable` is a backend-controlled monetization state.
- `bundle.sellable` is a backend-controlled monetization state.
- Sellability MUST NOT be implicit.
- Sellability requires all of:
  - valid ownership
  - valid pricing
  - valid Stripe mapping
  - backend approval
- A course or bundle with invalid or inconsistent monetization state MUST NOT be sellable.
- Frontend MAY display sellable state only as backend-projected truth.
- Fellable is a backend-computed state derived from validated teacher intent and system readiness conditions.

## 5. STRIPE PRODUCT MODEL

- Each sellable course maps to:
  - one Stripe product
  - one or more Stripe prices over time
- Each sellable bundle maps to:
  - one Stripe product
  - one or more Stripe prices over time
- Canonical mapping is backend-owned:
  - `course_id -> stripe_product_id`
  - `course_id -> active_stripe_price_id`
  - `bundle_id -> stripe_product_id`
  - `bundle_id -> active_stripe_price_id`
- Bundle Stripe mapping is separate from individual course Stripe mapping.
- A new price change MUST create a new Stripe price for future purchases.
- Historical purchases MUST remain tied to their original order/payment trail.
- Stripe product/price data supports payment collection only.
- Stripe product/price data MUST NOT become purchase or entitlement authority.

## 6. COURSE BUNDLE DOMAIN

- Bundles are first-class sellable products in MVP.
- A bundle is a teacher-defined product composed of multiple courses.
- A bundle grants course entitlement only.
- A bundle DOES NOT grant app access.
- A bundle DOES NOT modify `app.memberships`.
- Bundle fulfillment creates `course_enrollments` only.
- Allowed MVP bundle types are:
  - full step-series bundles
  - mixed-course bundles
- Full step-series bundles MAY include sequences such as step 1 + step 2 + step 3.
- Mixed-course bundles MAY include courses from different course groups.
- All courses in a bundle MUST belong to the same teacher in MVP.
- Cross-teacher bundles are forbidden in MVP.
- Bundle composition MUST be validated by backend.
- Teacher home bundle UI is composition intent only and MUST NOT define canonical bundle truth.

## 7. TEACHER SELLING EXPERIENCE LAW

- Teacher UI is the intent layer only.
- Backend is the only truth layer for selling configuration.
- Course editor pricing UI is NOT authority.
- Teacher home bundle UI is NOT authority.
- Canonical teacher selling flow is:
  1. teacher creates or edits a course
  2. teacher submits course pricing intent
  3. backend validates ownership and pricing
  4. backend persists canonical course monetization state
  5. backend creates or updates course Stripe product/price mapping
  6. backend marks the course sellable only after canonical requirements are met
  7. teacher creates a bundle from eligible same-teacher courses
  8. teacher submits bundle title, composition, and pricing intent
  9. backend validates bundle composition and pricing
  10. backend persists canonical bundle monetization state
  11. backend creates or updates bundle Stripe product/price mapping
  12. backend marks the bundle sellable only after canonical requirements are met
- UI MUST NOT create sellability truth from unsaved local state.
- UI MUST NOT rely on Stripe runtime/dashboard state as monetization truth.

## 8. PURCHASE FLOW

- Canonical paid course flow is:
  1. student initiates course purchase
  2. backend validates sellable course and current canonical price
  3. backend creates pending order in `app.orders`
  4. backend creates Stripe checkout/payment collection
  5. Stripe webhook confirms payment to backend
  6. backend marks the order as paid
  7. backend records payment in `app.payments`
  8. backend grants course entitlement in `course_enrollments`
- Canonical paid bundle flow is:
  1. student initiates bundle purchase
  2. backend validates sellable bundle and current canonical bundle price
  3. backend creates pending order in `app.orders`
  4. backend creates Stripe checkout/payment collection
  5. Stripe webhook confirms payment to backend
  6. backend marks the order as paid
  7. backend records payment in `app.payments`
  8. backend grants all bundle-defined course entitlements in `course_enrollments`
- Frontend checkout success is NOT authority.
- Stripe runtime status is NOT authority.
- Payment confirmation authority remains backend webhook completion only.

## 9. MEMBERSHIP SEPARATION

- Course sales DO NOT affect membership state.
- Bundle sales DO NOT affect membership state.
- Course sales DO NOT grant app access.
- Bundle sales DO NOT grant app access.
- Membership remains app-access-only authority under `app.memberships`.
- Courses and bundles remain content-entitlement commerce only.
- Course and bundle monetization MUST NOT be treated as membership purchase authority.

## 10. MARKETPLACE COMPATIBILITY

- This contract is compatible with future:
  - creator revenue attribution
  - payout accounting
  - seller reporting
  - marketplace governance
- None of those capabilities are implemented by this contract.
- Stripe Connect is NOT part of this contract.
- Payouts are NOT part of this contract.
- Seller settlement is NOT part of this contract.
- Any future marketplace or payout behavior requires a separate contract.

## 11. FAILURE MODEL

- Canonical failure categories include:
  - invalid course ownership
  - invalid pricing input
  - invalid bundle composition
  - duplicate or inconsistent Stripe mapping
  - Stripe product creation failure
  - Stripe price creation failure
  - attempt to include unauthorized course in bundle
  - attempt to use UI state as authority
- Backend MUST always validate monetization setup.
- Frontend MUST NEVER fall back to self-defined pricing truth.
- Stripe MUST NEVER become authority when setup fails.
- A failed monetization setup MUST NOT create sellability or purchase authority.

## 12. FORBIDDEN PATTERNS

- Frontend pricing authority.
- Frontend sellability authority.
- Teacher UI as final monetization authority.
- Stripe as pricing, sellability, purchase, or entitlement authority.
- Implicit sellability without backend validation and approval.
- Bundle purchase modifying `app.memberships`.
- Course purchase modifying `app.memberships`.
- Cross-teacher bundles in MVP.
- Reusing bundle Stripe mapping as if it were individual course sellability truth.
- Mutating historical purchase truth by changing current price mappings.
- Polymorphic purchase authority that collapses course, bundle, and membership into one canonical meaning.

## 13. FINAL ASSERTION

- This contract is the canonical course monetization and teacher pricing truth for launch scope.
- It is lockable as a contract artifact.
- Contract truth and implementation drift are intentionally separated.
