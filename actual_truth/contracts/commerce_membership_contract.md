# COMMERCE MEMBERSHIP CONTRACT

## STATUS

ACTIVE

This contract defines the canonical commerce truth for launch purchase authority, membership purchase/current membership state, payment UI boundaries, and adjacent MVP bundle separation.
This contract operates under `SYSTEM_LAWS.md`.
Post-auth entry authority and routing composition are owned by `onboarding_entry_authority_contract.md`.

## 1. CONTRACT LAW

- Purchase authority is owned only by `app.orders` and `app.payments`.
- Membership current-state truth is owned only by `app.memberships`.
- Membership state is an input to entry composition, not full app-entry authority by itself.
- Membership purchase is a purchase flow and therefore MUST create an order.
- Membership MUST NOT exist as a separate purchase authority.
- Course purchase and membership purchase use separate canonical initiation entrypoints.
- Stripe webhook completion is the only canonical payment-confirmation path.
- Stripe MAY be embedded in Aveli UI for payment collection only and this MUST NOT change authority.
- Course bundles are included in MVP as a separate order-backed and payment-backed commerce domain.
- Notification audiences MUST preserve separation between membership authority and course-access authority.

## 2. AUTHORITY MODEL

- `app.orders` owns purchase identity and lifecycle for all paid launch commerce flows.
- `app.payments` owns payment-provider settlement records tied to orders.
- `app.memberships` owns current membership state only.
- `course_enrollments` owns protected course entitlement and access state for course and course-bundle fulfillment.
- `app.memberships` is the single canonical current-state membership authority per user.
- `app.memberships` MUST contain exactly one authority row per `user_id`.
- The `app.memberships` authority row represents only the current membership state.
- Current membership authority MUST NOT be derived by aggregating multiple membership rows.
- Current membership authority MUST NOT depend on Stripe runtime state.
- Historical membership transitions are not part of MVP authority and MAY be introduced later only by a separate event/history contract.
- `app.memberships` does not own purchase truth.
- A membership row is not proof of purchase without an order/payment trail.

Protected course-access state, including course-bundle-granted course entitlement state, is outside membership authority and is owned only by `course_access_contract.md`.
Full post-auth entry composition, routing, and the `GET /entry-state`
`membership_active` projection are owned by
`onboarding_entry_authority_contract.md`.

## Payment Tables Classification

app.payment_events:
- TYPE: SUPPORT_TABLE
- ROLE: webhook idempotency + observability
- AUTHORITY: NONE
- WRITE: backend webhook only
- READ: observability layer allowed
- REQUIRED: YES

app.billing_logs:
- TYPE: SUPPORT_TABLE
- ROLE: billing observability/logging
- AUTHORITY: NONE
- WRITE: backend only
- READ: observability layer allowed
- REQUIRED: YES

app.transactions:
- TYPE: REMOVED
- ROLE: deprecated
- AUTHORITY: NONE
- MUST NOT EXIST in baseline

app.subscriptions:
- TYPE: REMOVED
- ROLE: deprecated
- AUTHORITY: NONE
- MUST NOT EXIST in baseline

## 3. CANONICAL MEMBERSHIP-SCOPE ENTRYPOINTS

- Course purchase initiation: `POST /api/checkout/create`
- Membership purchase initiation: `POST /api/billing/create-subscription`
- Stripe webhook completion: `POST /api/stripe/webhook`

Entrypoint responsibilities:

- `POST /api/checkout/create` initiates paid course purchase only.
- `POST /api/billing/create-subscription` initiates membership purchase only.
- `POST /api/stripe/webhook` confirms payment and applies post-payment mutations.
- Course bundles are included in MVP as a separate domain and do not change these locked membership-scope entrypoints.

## 4. COURSE PURCHASE FLOW

1. Client calls `POST /api/checkout/create`.
2. Backend validates the course purchase request.
3. Backend resolves the course and Stripe price.
4. Backend creates a pending order in `app.orders`.
5. Backend creates a Stripe checkout session.
6. Backend stores Stripe checkout references on the order.
7. Backend returns checkout session data to the client.
8. Stripe sends the completion event to `POST /api/stripe/webhook`.
9. Webhook marks the order as paid.
10. Webhook records payment in `app.payments`.
11. Webhook creates canonical course-access state under `course_access_contract.md`.
12. Membership is not changed by the course purchase flow.

## 5. MEMBERSHIP PURCHASE FLOW

1. Client calls `POST /api/billing/create-subscription`.
2. Backend validates the membership purchase request.
3. Backend resolves the membership Stripe price.
4. Backend creates a pending order in `app.orders`.
5. Backend creates a Stripe subscription checkout session.
6. Backend stores order linkage in Stripe metadata.
7. Backend ensures the single canonical current-state row in `app.memberships` remains non-access-granting until canonical payment confirmation is applied.
8. Backend returns checkout session data to the client.
9. Stripe sends subscription and invoice events to `POST /api/stripe/webhook`.
10. Webhook resolves the event back to the membership purchase order.
11. Webhook marks the order as paid.
12. Webhook records payment in `app.payments`.
13. Webhook updates `app.memberships` to the canonical membership state.

## 6. PAYMENT UI MODEL

- Stripe MAY be embedded in Aveli UI for payment collection, including Stripe Elements or equivalent embedded collection surfaces.
- Payment UI MUST remain fully hosted on an Aveli-controlled domain.
- Frontend MAY collect payment details.
- Frontend MAY confirm a payment intent with Stripe for payment collection execution.
- Frontend MUST NOT grant app access.
- Frontend MUST NOT mutate membership state.
- Frontend MUST NOT treat Stripe success as membership authority.
- Payment success in frontend is NOT membership authority.
- Membership state MUST ONLY change after backend validates the Stripe webhook and backend persists the membership update.
- Backend remains the ONLY authority for membership state.
- Backend remains the ONLY authority for commerce membership-state decisions.
- Final app-entry and routing decisions remain owned by `GET /entry-state`
  under `onboarding_entry_authority_contract.md`.
- Stripe remains payment processor and event emitter only.
- Stripe is NOT membership authority.
- Stripe is NOT access authority.

## 7. COURSE BUNDLES DOMAIN

- Course bundles are included in MVP.
- Course bundles are a separate domain from membership.
- Course bundles grant course entitlement only.
- Course bundles DO NOT grant app access.
- Course bundles DO NOT affect membership state.
- Course bundles MUST be order-backed.
- Course bundles MUST be payment-backed.
- Course bundles MUST NOT modify `app.memberships`.
- Course bundles MUST NOT influence onboarding or auth.
- Course access remains governed only by `course_enrollments` as canonical authority under `course_access_contract.md`.
- Bundle fulfillment MUST resolve through `app.orders` and `app.payments` before mutating course-access state.

## 8. MEMBERSHIP ALIGNMENT DECISION

- Membership purchase MUST create order.
- Membership purchase MUST NOT be a separate non-order purchase authority.
- Canonical non-purchase membership grants may exist only when explicitly
  authorized by contract.
- The canonical purchase trail for membership is:
  - `app.orders` for purchase identity and state
  - `app.payments` for payment settlement
  - `app.memberships` for resulting current membership state
- Canonical non-purchase membership grants for this onboarding path are owned
  only by `referral_membership_grant_contract.md`.
- Any purchase-backed membership flow that creates or updates membership
  without an order-backed purchase trail is non-canonical.

## 9. MEMBERSHIP SOURCE LAW

Membership must always have an explicit source.

Allowed sources:

- purchase
- coupon
- referral

Rules:

- purchase MUST create an order
- purchase MAY include a trial period
- trial via Stripe is still a purchase and MUST have an order
- coupon MUST NOT create an order unless a later explicit contract says
  otherwise
- referral MUST NOT create an order
- referral MUST NOT create payment truth
- referral is the sole canonical non-purchase grant doctrine relevant to this
  onboarding path
- all memberships MUST include explicit source metadata
- implicit membership creation is forbidden

## 10. MEMBERSHIP LIFECYCLE

Canonical membership current-state statuses are:

- `inactive`
- `active`
- `past_due`
- `canceled`
- `expired`

State meaning:

- `inactive` = no valid current membership entitlement; membership input is inactive
- `active` = valid current membership entitlement; membership input is active
- `past_due` = delinquent payment state; membership input is inactive immediately
- `canceled` = renewal has been stopped but the current entitlement remains valid until `expires_at`
- `expired` = membership entitlement has ended; membership input is inactive

Lifecycle rules:

- `inactive -> active` is allowed only after canonical backend confirmation of a valid paid or non-purchase membership grant
- `active -> past_due` is allowed only after canonical backend confirmation of delinquent renewal state
- `past_due -> active` is allowed only after canonical backend confirmation of payment recovery
- `active -> canceled` is allowed only after canonical backend confirmation that renewal will not continue
- `canceled -> active` is allowed only after canonical backend confirmation of reactivation or a new valid membership term
- `canceled -> expired` is allowed only when `expires_at` has been reached
- `past_due -> expired` is allowed only when delinquency becomes terminal without recovery
- `expired -> active` is allowed only after canonical backend confirmation of a new valid paid or non-purchase membership grant
- Checkout initiation, frontend state, and Stripe runtime status alone MUST NOT grant access or act as membership authority
- No grace period exists in MVP for `past_due`
- Any future grace-period behavior MUST require a separate explicit contract and MUST NOT be inferred from Stripe retry logic

## 11. MEMBERSHIP STATE INPUT TO ENTRY

This contract defines the membership current-state rule consumed by
`onboarding_entry_authority_contract.md`. Membership state is not full app-entry
authority by itself.

Membership state evaluates as active for entry composition only when:

- `status = active`
- OR `status = canceled AND current_time < expires_at`

All other states MUST evaluate as inactive for entry composition:

- `inactive`
- `past_due`
- `expired`

Membership input rules:

- `past_due` means membership state is inactive immediately.
- membership state MUST evaluate as inactive when `status = past_due`.
- membership state MUST be determined only from the backend-owned current state in `app.memberships`.
- `GET /entry-state` under `onboarding_entry_authority_contract.md` owns final app-entry and routing composition.
- Membership alone MUST NOT grant app entry.

## 12. NOTIFICATION AUDIENCE LAW

- Membership and course access are separate authorities.
- Membership determines membership-scope audience eligibility.
- Membership does not determine final app entry by itself.
- `course_enrollments` determines course-level access.
- `course_enrollments` determines course-level audience.
- Notifications MUST use membership for global app announcements.
- Notifications MUST use membership for member-wide targeting.
- Notifications MUST use `course_enrollments` for course-specific targeting.
- Notifications MUST NOT use membership to infer course access.
- Notifications MUST NOT use course enrollment to infer app entry.
- Notifications MUST NOT mix membership and enrollment audiences.

## 13. FORBIDDEN PATTERNS

- A single checkout endpoint serving both course and membership via a `type` switch.
- Service checkout logic inside canonical launch commerce entrypoints.
- Membership purchase without order creation.
- Membership as standalone purchase authority.
- Multiple authority rows per `user_id` in `app.memberships`.
- Aggregation-based derivation of current membership authority across multiple rows.
- Webhook flows that update membership without resolving purchase authority through orders/payments.
- Webhook flows that create fallback purchase authority outside the canonical order path.
- Duplicate membership initiation entrypoints that express the same purchase meaning.
- Treating `subscription` as the canonical runtime authority term.
- Treating `past_due` as access-granting or grace-bearing by default.
- Inferring a grace period from Stripe retry behavior without a separate explicit contract.
- Treating session-status, portal, or cancellation surfaces as launch purchase entrypoints.
- Treating embedded Stripe UI success as membership authority.
- Letting frontend mutate membership state after direct Stripe confirmation.
- Letting course bundles grant app access or mutate `app.memberships`.
- Using membership to infer course-level notification audience.
- Using course enrollment to infer app-level audience.
- Mixing membership and course-enrollment audiences as a single canonical audience authority.

## 14. FRONTEND ALIGNMENT TARGET

- Frontend must use `POST /api/checkout/create` only for paid course purchase.
- Frontend must use `POST /api/billing/create-subscription` only for membership purchase.
- Frontend must never use `POST /api/checkout/create` for membership purchase.
- Frontend must never use `POST /api/checkout/create` for service purchase in launch scope.
- Frontend must treat `POST /api/stripe/webhook` as backend-only.
- Frontend MAY embed Stripe Elements or equivalent embedded Stripe payment UI within an Aveli-hosted payment surface.
- Frontend embedded payment UI MUST remain non-authoritative.
- Frontend payment success or payment-intent confirmation MUST NOT grant app access.
- Frontend must not depend on polymorphic request bodies.
- Frontend course purchase request shape:
  - `{ "slug": string }`
- Frontend membership purchase request shape:
  - `{ "interval": "month" | "year" }`
- Frontend course purchase response shape:
  - `{ "url": string, "session_id": string, "order_id": string }`
- Frontend membership purchase response shape:
  - `{ "url": string, "session_id": string, "order_id": string }`
- All checkout responses MUST follow the same response shape regardless of purchase type.

## 15. IMPLEMENTATION DRIFT OUTSIDE CONTRACT

- `POST /api/stripe/webhook` currently handles broader mixed-domain branches beyond the clean separations locked by this contract.

## 16. REFUND, WITHDRAWAL, CANCELLATION, AND ACCESS-REVOCATION LAW

- Membership is a subscription purchase and remains order-backed and payment-backed.
- One-off digital product purchase means an order-backed and payment-backed purchase of course or bundle entitlement.
- Backend is the only authority allowed to:
  - trigger refund workflow
  - mark subscription cancellation effect
  - decide when membership access ends
  - decide when one-off product access ends
  - revoke access following a valid withdrawal outcome or separate statutory remedy outcome
- Stripe is infrastructure and transport only.
- Stripe subscription state, invoice state, charge state, refund state, dispute state, checkout-session state, customer-portal state, and webhook payload shape are never authority by themselves.
- Frontend state is never refund authority, cancellation-state authority, or access-revocation authority.
- Token claims are never refund authority, cancellation-state authority, or access-revocation authority.
- Ad hoc support surfaces, support notes, CRM state, and manual support acknowledgments are never refund authority, cancellation-state authority, or access-revocation authority.

Membership subscription cancellation law:

- Cancellation after the legally applicable withdrawal window stops future automatic charging only.
- Cancellation after the legally applicable withdrawal window does not by itself refund already-paid completed periods.
- Cancellation after the legally applicable withdrawal window does not by itself revoke already-paid membership access before the canonical entitlement end boundary.
- Membership access remains valid until the end of the already-paid period if canonical backend state remains `active`, or `canceled` with `current_time < expires_at`, unless a valid withdrawal outcome or separate statutory remedy outcome requires earlier revocation.
- Stripe-side cancel intent or Stripe-side cancel acknowledgement is not canonical membership state by itself.

Membership valid-withdrawal law:

- A valid withdrawal within the legally applicable withdrawal window is distinct from ordinary cancellation.
- When backend determines that a membership withdrawal outcome is valid, backend MUST:
  - stop future automatic charging
  - trigger refund handling for the relevant charge according to the legally valid withdrawal outcome
  - revoke membership access immediately through canonical backend-owned state in `app.memberships`
- Refund, withdrawal, or cancellation does not automatically imply deletion of user data; retention and deletion belong to a separate policy layer.

One-off digital product withdrawal law:

- A valid withdrawal within the legally applicable withdrawal window for a one-off digital product purchase MUST trigger backend refund handling and immediate access revocation.
- Immediate one-off access revocation MUST occur only through canonical backend-owned access mutation under `course_access_contract.md`.
- After the legally applicable withdrawal window, no refund exists solely because of change of mind.

Remedy separation law:

- Withdrawal rights are separate from defect, delivery failure, dispute handling, chargeback handling, fraud handling, mandatory statutory consumer remedies, and other legally required remedies.
- Nothing in this contract may be used to deny or block a separate defect, dispute, or statutory remedy path.
- A separate defect, dispute, or statutory remedy outcome may still trigger refund handling or access revocation, but only through canonical backend-owned authority.

Authority effect law:

- Membership access authority remains `app.memberships`.
- Product access authority remains the canonical purchase/result substrate and resulting access tables, not Stripe state.
- Refund, withdrawal, cancellation, and remedy handling must never bypass canonical backend access authority.

## 17. FINAL ASSERTION

- This contract is the canonical launch commerce and membership purchase truth.
- This contract does not own full post-auth entry composition or routing authority.
- Membership state is an input to `GET /entry-state` under `onboarding_entry_authority_contract.md`.
- It is lockable as a contract artifact.
- Contract truth and implementation drift are intentionally separated.
