# Embedded Checkout Activation Decision

## STATUS

ACTIVE ACTIVATION DECISION.

NO-CODE DECISION ONLY.

This file activates the embedded Stripe checkout implementation path for
ordinary purchase-backed membership checkout before code changes begin.

It does not implement backend, frontend, baseline, test, or deployment changes.
It does not change referral, coupon, course, bundle, or marketplace commerce
doctrine.

## 1. AUTHORITY LOAD

Authority used:

- `actual_truth/contracts/commerce_membership_contract.md`
- `actual_truth/contracts/onboarding_entry_authority_contract.md`
- `actual_truth/contracts/onboarding_contract.md`
- `actual_truth/contracts/auth_onboarding_contract.md`
- `actual_truth/contracts/ratifications/T14_membership_trial_duration_decision.md`
- `actual_truth/contracts/aveli_embedded_checkout_spec.md`
- `actual_truth/analysis/AUDIT_EXISTING_CHECKOUT_AND_STRIPE_SURFACES.md`

Supporting current-state evidence from the audit:

- current membership checkout starts at `POST /api/billing/create-subscription`
- current membership checkout response is `{ "url": string, "session_id": string, "order_id": string }`
- current frontend opens backend-created Stripe URLs through WebView where supported
- current repo does not yet have a membership `client_secret` checkout response
- current repo does not yet have an Aveli-hosted embedded checkout shell
- webhook settlement remains the canonical payment confirmation path
- `app.orders` owns purchase identity
- `app.payments` owns payment settlement
- `app.memberships` owns current membership state
- `GET /entry-state` owns post-auth payment and onboarding routing truth

Ratified trial-duration evidence:

- `T14_membership_trial_duration_decision.md` ratifies ordinary purchase-backed
  membership checkout to a 14-day trial/test period with card details required.
- This decision does not reopen that 14-day ratification.

## 2. EXECUTIVE VERDICT

PASS.

Embedded Stripe checkout becomes the active canonical implementation path for
ordinary purchase-backed membership checkout.

The active membership checkout model is:

`Aveli-hosted embedded Stripe checkout shell + backend-created Stripe Checkout Session + webhook-owned settlement`

The existing raw Stripe-hosted URL / raw WebView membership checkout path is
superseded as the canonical ordinary membership checkout path.

Course and bundle checkout are outside this activation and stay on their
current hosted checkout path until a separate course/bundle checkout decision
exists.

## 3. CURRENT MEMBERSHIP CHECKOUT AUTHORITY

Current authority before this activation:

- membership purchase initiation: `POST /api/billing/create-subscription`
- request shape: `{ "interval": "month" | "year" }`
- response shape: `{ "url": string, "session_id": string, "order_id": string }`
- purchase authority: `app.orders`
- payment settlement authority: `app.payments`
- current membership authority: `app.memberships`
- payment confirmation authority: `POST /api/stripe/webhook`
- post-auth routing authority: `GET /entry-state`

Current implementation state:

- membership checkout currently creates a Stripe hosted checkout session
- membership checkout currently returns a Stripe checkout URL
- frontend currently opens that URL through the existing checkout WebView route
  where supported
- checkout success, return, or cancel state refreshes backend truth and is not
  membership or app-entry authority

This current implementation remains repo reality until implementation changes
are made, but it is no longer the selected canonical implementation target for
ordinary membership checkout after this activation decision.

## 4. EMBEDDED CHECKOUT ACTIVATION DECISION

Decision:

Embedded Stripe checkout is active for ordinary purchase-backed membership
checkout.

The activated target flow is:

1. Ordinary user registers with email and password.
2. Frontend reads `GET /entry-state`.
3. If `needs_payment = true`, frontend routes to the membership checkout-start
   surface.
4. Frontend calls `POST /api/billing/create-subscription` with
   `{ "interval": "month" | "year" }`.
5. Backend creates a pending membership purchase order in `app.orders`.
6. Backend creates a Stripe subscription Checkout Session configured for
   embedded checkout and the ratified 14-day trial with card details required.
7. Backend returns embedded checkout launch data.
8. Frontend renders an Aveli-hosted embedded checkout shell.
9. Stripe embedded checkout collects payment details only.
10. Stripe webhook remains the only payment-confirmation and settlement path.
11. Backend webhook settles `app.orders`, records `app.payments`, and updates
    `app.memberships` when Stripe confirmation is valid.
12. Frontend success/return state refreshes `GET /entry-state`.
13. If membership is webhook-confirmed and onboarding is still incomplete,
    routing proceeds to create-profile through `GET /entry-state`.

Frontend may render an Aveli-hosted embedded checkout shell.

Frontend must not:

- grant app access
- mutate membership
- write onboarding state
- treat Stripe success as membership authority
- route from `/profiles/me`
- skip create-profile
- skip welcome confirmation

Backend remains canonical for:

- order creation
- Stripe session creation
- payment confirmation
- payment settlement
- membership state
- entry-state routing truth

## 5. CANONICAL RESPONSE SHAPE DECISION

Chosen canonical ordinary membership checkout response shape:

```json
{
  "client_secret": "string",
  "session_id": "string",
  "order_id": "string"
}
```

This replaces the legacy membership checkout response shape:

```json
{
  "url": "string",
  "session_id": "string",
  "order_id": "string"
}
```

Rules:

- `client_secret` is the short-lived Stripe embedded Checkout Session secret
  returned only by the authenticated membership checkout initiation response.
- `session_id` remains required for Stripe/session correlation and frontend
  return-state tracking.
- `order_id` remains required for backend purchase identity correlation and
  observability.
- `url` is not part of the canonical ordinary membership checkout success
  response after embedded activation.
- Frontend must not infer authority from `client_secret`, `session_id`, or
  `order_id`.
- Webhook-confirmed backend state remains required before membership or entry
  state can change.

Route decision:

- Keep `POST /api/billing/create-subscription` as the single membership
  purchase initiation endpoint.
- Change its ordinary membership checkout response shape to
  `{ "client_secret", "session_id", "order_id" }`.
- Do not create a second membership checkout initiation route for the same
  purchase meaning.

Rationale:

- `commerce_membership_contract.md` forbids duplicate membership initiation
  entrypoints that express the same purchase meaning.
- Keeping the existing route preserves the canonical membership purchase
  entrypoint while changing only the response transport needed for embedded
  checkout.

## 6. HOSTED/WEBVIEW PATH STATUS

Membership checkout:

- Raw Stripe-hosted URL checkout is superseded as the canonical ordinary
  membership checkout path.
- Raw Stripe URL WebView loading is superseded as the canonical ordinary
  membership checkout renderer.
- No temporary hosted-Stripe fallback is activated by this decision.

Allowed WebView use after activation:

- Mobile may use the existing WebView capability only to load an Aveli-hosted
  embedded checkout shell.
- Loading a raw Stripe-hosted checkout URL through WebView is not the canonical
  ordinary membership checkout path after this decision.

Fallback rule:

- Any future hosted membership fallback requires a separate explicit fallback
  decision that defines response shape, platform scope, failure semantics, and
  tests.
- Hosted fallback must not silently re-enter through the embedded membership
  response shape.

## 7. MEMBERSHIP VS COURSE/BUNDLE SCOPE DECISION

Scope:

Membership checkout only.

This activation applies only to ordinary purchase-backed membership checkout
through `POST /api/billing/create-subscription`.

Out of scope:

- paid course checkout through `POST /api/checkout/create`
- bundle checkout through `POST /api/course-bundles/{bundle_id}/checkout-session`
- course or bundle entitlement fulfillment
- course or bundle checkout response shape
- course or bundle hosted checkout transport

Course and bundle checkout remain on the current hosted checkout path for now.

Course and bundle checkout must not be pulled into the embedded membership
implementation unless a later explicit course/bundle embedded checkout decision
exists.

## 8. CONTRACTS THAT MUST BE UPDATED

Before implementation begins, update the active contract stack so no active
contract still presents the superseded ordinary membership checkout model as
canonical.

Required contract updates:

- `actual_truth/contracts/commerce_membership_contract.md`
  - replace ordinary membership checkout response shape with
    `{ "client_secret", "session_id", "order_id" }`
  - replace ordinary 30-day trial references with the ratified 14-day rule
  - state that embedded checkout is canonical for ordinary membership checkout
  - state that hosted/raw URL membership checkout is superseded
  - preserve order-backed purchase authority, webhook settlement, and
    membership authority

- `actual_truth/contracts/onboarding_contract.md`
  - replace 30-day ordinary membership checkout trial text with the ratified
    14-day rule
  - preserve checkout-before-create-profile routing intent
  - preserve checkout as non-entry and non-onboarding authority

- `actual_truth/contracts/aveli_embedded_checkout_spec.md`
  - remove `PENDING TRIAL-DURATION RATIFICATION`
  - update current-truth language so 14 days is ratified
  - identify this activation decision as the authority that activates embedded
    membership checkout
  - keep course/bundle checkout out of scope unless a later decision expands it

Required derived-task updates after contract alignment:

- `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/T13_lock_and_implement_ordinary_checkout_welcome_flow.md`
- `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/task_manifest.json`
- checkout/onboarding payment task surfaces that still require 30 days, hosted
  membership URL response, or missing embedded response-shape coverage

These derived-task updates must follow the updated active contracts. They must
not redefine the decision.

## 9. STOP CONDITIONS

STOP before implementation if any of the following is true:

- more than one active ordinary membership checkout model is kept
- the membership checkout response shape is not exactly chosen
- a hosted membership URL response remains canonical for ordinary membership
  checkout
- a new duplicate membership initiation route is introduced for the same
  purchase meaning
- course or bundle checkout is silently moved to embedded checkout by this
  membership decision
- any implementation uses a 30-day ordinary membership checkout trial
- frontend checkout success, Stripe success, return URL state, `client_secret`,
  `session_id`, or `order_id` is treated as membership authority
- checkout writes onboarding state
- checkout completes onboarding
- `/profiles/me` becomes routing, checkout, payment, onboarding, or membership
  authority
- Stripe webhook settlement is bypassed
- backend cannot create an embedded Stripe Checkout Session with a
  `client_secret` under the Stripe API version used by the repo
- tests do not cover embedded response shape, 14-day trial, required card
  collection, webhook-only membership activation, and frontend non-authority

## 10. FINAL NEXT STEP

Next step:

Update the active contracts listed in section 8, then implement the embedded
Stripe membership checkout flow.

Implementation must start only after the active contract stack is aligned with:

- embedded membership checkout active
- one membership checkout initiation endpoint
- one canonical membership checkout response shape:
  `{ "client_secret", "session_id", "order_id" }`
- ratified 14-day trial with card details required
- hosted/raw Stripe URL membership checkout superseded
- course and bundle checkout remaining on current hosted path
- webhook-owned settlement and membership mutation preserved
