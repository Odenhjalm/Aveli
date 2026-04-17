# Aveli Embedded Checkout Spec

## Status

ACTIVE TARGET SPECIFICATION.

This specification is subordinate to
`actual_truth/contracts/baseline_v2_authority_freeze_contract.md`,
`actual_truth/contracts/commerce_membership_contract.md`, and
`actual_truth/contracts/embedded_checkout_activation_decision.md`.

ACTIVATED FOR ORDINARY MEMBERSHIP CHECKOUT BY
`actual_truth/contracts/embedded_checkout_activation_decision.md`.

TRIAL DURATION RATIFIED BY
`actual_truth/contracts/ratifications/T14_membership_trial_duration_decision.md`.

This file is the active target specification for ordinary purchase-backed
membership checkout at the contract layer. It does not implement code, mutate
baseline, or expand embedded checkout scope to course, bundle, service,
session, or Connect checkout.

Implementation-plan and prompt sections that predate Baseline V2 freeze are
historical until regenerated after the authority-freeze batches are accepted.

## 1. Current-State Audit Summary

The repo currently supports backend-authoritative Stripe Checkout:

- membership checkout starts at `POST /api/billing/create-subscription`
- course checkout starts at `POST /api/checkout/create`
- bundle checkout starts at
  `POST /api/course-bundles/{bundle_id}/checkout-session`
- payment confirmation is owned by `POST /api/stripe/webhook`
- purchase identity is owned by `app.orders`
- payment settlement is owned by `app.payments`
- current membership state is owned by `app.memberships`
- post-auth routing is owned by `GET /entry-state`
- `/profiles/me` remains projection-only

The pre-implementation frontend/runtime opens backend-created Stripe checkout
URLs through an in-app WebView where supported. That is implementation drift
for ordinary membership checkout after embedded checkout activation, not the
canonical target model.

## 2. Existing Checkout / Stripe Surfaces Found In Repo

Backend surfaces:

- `backend/app/routes/billing.py`
- `backend/app/services/subscription_service.py`
- `backend/app/schemas/billing.py`
- `backend/app/routes/api_checkout.py`
- `backend/app/services/checkout_service.py`
- `backend/app/routes/course_bundles.py`
- `backend/app/services/course_bundles_service.py`
- `backend/app/routes/stripe_webhooks.py`
- `backend/app/services/stripe_webhook_membership_service.py`
- `backend/app/services/stripe_webhook_course_service.py`
- `backend/app/services/stripe_webhook_bundle_service.py`
- `backend/app/stripe_mode.py`
- `backend/app/config.py`

Frontend surfaces:

- `frontend/lib/features/payments/presentation/subscribe_screen.dart`
- `frontend/lib/features/paywall/data/checkout_api.dart`
- `frontend/lib/features/paywall/application/checkout_flow.dart`
- `frontend/lib/features/paywall/presentation/checkout_webview_page.dart`
- `frontend/lib/features/paywall/presentation/checkout_result_page.dart`
- `frontend/lib/core/deeplinks/deep_link_service.dart`
- `frontend/lib/core/routing/app_router.dart`
- `frontend/lib/core/routing/route_paths.dart`
- `frontend/lib/core/routing/route_session.dart`

Baseline/support surfaces:

- `backend/supabase/baseline_slots/0029_canonical_purchase_substrate_foundation.sql`
- `backend/supabase/baseline_slots/0034_payment_events_webhook_idempotency_support.sql`
- `backend/supabase/baseline_slots/0036_restore_billing_logs.sql`
- `backend/supabase/baseline_slots/0037_memberships_referral_source_alignment.sql`

## 3. Missing Pieces And Drift

- Implementation drift: backend code may still encode the superseded 30-day
  ordinary membership checkout trial until implementation alignment. Contract
  truth is now the ratified 14-day trial/test period.
- Runtime membership checkout response returns `url`, not `client_secret`.
- Frontend checkout launch model has no `clientSecret`.
- No Aveli-hosted embedded checkout shell exists.
- Current WebView loads Stripe URL directly, not an Aveli-hosted embedded
  checkout shell.
- Current checkout copy does not state trial length, card requirement, or
  membership contents.
- Course and bundle checkout remain outside this embedded membership scope and
  continue to expect hosted Checkout URL behavior.
- Tests do not assert card collection or trial-day configuration.
- Tests do not cover embedded checkout response shape.

## 4. Recommended Embedded Stripe Architecture For Aveli

Use an Aveli-hosted checkout shell plus Stripe embedded Checkout.

Flow:

1. Ordinary user registers with email and password.
2. Router reads `GET /entry-state`.
3. If `needs_payment = true`, route user to the checkout-start surface.
4. Checkout-start surface calls `POST /api/billing/create-subscription`.
5. Backend creates a pending membership purchase order in `app.orders`.
6. Backend creates a Stripe subscription Checkout Session configured for
   embedded payment collection and the ratified 14-day trial/test period.
7. Backend returns
   `{ "client_secret": "string", "session_id": "string", "order_id": "string" }`.
8. Frontend opens or renders an Aveli-owned checkout shell.
9. The Aveli shell mounts Stripe embedded Checkout with `client_secret`.
10. Stripe collects card/payment details.
11. Frontend return/success/cancel state refreshes backend state only.
12. Stripe webhook remains the only settlement and membership mutation path.
13. After webhook-confirmed membership activation, `GET /entry-state` routes
    the user to create-profile.

Implementation rule:

- Do not mix embedded/custom Checkout modes with hosted
  `success_url`/`cancel_url` assumptions.
- Do not return a hosted or raw Stripe URL as the canonical ordinary
  membership checkout response.
- Use the Stripe return model required by the selected embedded Checkout mode.
- Stripe is a payment renderer and event emitter only.
- Backend webhook remains membership authority.
- `GET /entry-state` remains routing authority.

Simple platform split:

- Flutter web may render the Aveli shell directly if Stripe.js is available.
- Mobile may load the Aveli-hosted checkout shell through the existing WebView.
- Desktop unsupported states must be deterministic and Swedish unless desktop
  checkout is separately accepted.

## 5. Page Layout And UX Structure

Route target:

- Keep `/subscribe` as the current mounted checkout-start route unless a route
  rename is separately ratified.
- The user-facing page title should say `Medlemskap`.
- Product copy should describe payment/checkout, not create a separate
  subscription journey.

Layout:

- Full-height Aveli checkout page.
- Aveli logo above the content.
- Desktop: two columns, with membership promise on the left and Stripe embedded
  payment panel on the right.
- Mobile: one column, with logo, trial promise, benefits, and embedded payment.
- Trust line below payment panel.
- No nested cards.
- No local app-entry button after checkout.

States:

- Loading: backend is creating checkout.
- Error: retryable checkout creation failure.
- Cancel: membership remains unchanged.
- Success before webhook: waiting/retry state.
- Success after webhook: route via `GET /entry-state`.

## 6. Swedish Copy Block For Checkout Page

Primary headline:

```text
Starta ditt medlemskap i Aveli
```

Trial/card line:

```text
Du får 14 dagar att testa appen. Kortuppgifter krävs, men du debiteras inte under provperioden.
```

Membership contents:

```text
I medlemskapet ingår:

Live lektioner
Tillgång till ett stort kursutbud och en plattform för likasinnade spirituellt intresserade människor i olika skeden av sin utveckling
Meditationsmusik och guidade meditationer
En trygg plats för lärande och spirituell utveckling
```

Trust copy:

```text
Betalningen hanteras säkert av Stripe. Aveli uppdaterar din åtkomst först när betalningen har bekräftats av servern.
```

Action:

```text
Fortsätt till betalning
```

Loading:

```text
Förbereder din säkra betalning...
```

Waiting for backend confirmation:

```text
Vi bekräftar ditt medlemskap. Det kan ta en kort stund innan betalningen är klar hos Stripe.
```

Retry:

```text
Kontrollera igen
```

Cancel:

```text
Betalningen avbröts. Din åtkomst ändras inte.
```

Post-confirmation:

```text
Ditt medlemskap är bekräftat. Nu fortsätter du med att skapa din profil.
```

Welcome confirmation, owned by onboarding:

```text
Jag förstår hur Aveli fungerar
```

## 7. Visual Styling Direction

- Calm, premium Aveli feel.
- Light blue to muted purple background.
- Aveli logo visible.
- White or near-white embedded payment panel.
- Restrained shadows.
- Border radius maximum 8px for buttons and cards.
- Current app typography and spacing.
- Avoid dark blue/slate dominance.
- Avoid beige/cream/sand/brown dominance.
- Avoid decorative orb or bokeh backgrounds.
- Stripe form should feel embedded in Aveli, not like an external browser.

## 8. Routing And Flow After Register

Canonical ordinary path:

`register -> checkout -> create-profile -> welcome -> onboarding-complete -> app`

After `POST /auth/register`:

- Backend creates auth identity, application subject, projection row, and
  session.
- Backend does not create membership.
- Backend does not complete onboarding.
- Frontend fetches `GET /entry-state`.
- Ordinary user should have `needs_payment = true`,
  `needs_onboarding = true`, and `onboarding_state = "incomplete"`.
- Routing precedence sends the user to checkout before create-profile.

## 9. Routing And Flow After Successful Checkout

Successful checkout means backend-confirmed membership state, not frontend
success state.

Flow:

1. Stripe embedded checkout returns to Aveli.
2. Frontend refreshes `GET /entry-state`.
3. If webhook has not updated membership, stay on waiting state.
4. If webhook has updated `app.memberships` to active purchase-backed trial
   membership, `GET /entry-state` should return:
   - `membership_active = true`
   - `needs_payment = false`
   - `needs_onboarding = true`
   - `onboarding_state = "incomplete"`
5. Router sends user to `/create-profile`.

Frontend must not:

- set membership locally
- set `can_enter_app`
- skip create-profile
- use `/profiles/me` as routing authority

## 10. Interaction With Create-Profile, Welcome, And Onboarding-Complete

After checkout:

- User creates profile through `POST /auth/onboarding/create-profile`.
- Required name lives at create-profile.
- Bio remains optional.
- Image remains optional and media-mediated.
- `/profiles/me` remains projection-only.
- Successful create-profile moves `app.auth_subjects.onboarding_state` to
  `welcome_pending`.
- Router sends `welcome_pending` users to `/welcome`.
- Welcome confirmation triggers `POST /auth/onboarding/complete`.
- Onboarding completion writes
  `app.auth_subjects.onboarding_state = "completed"`.
- App entry is allowed only when `GET /entry-state` returns
  `can_enter_app = true`.

## 11. Data And Authority Boundaries

Checkout/payment authority:

- Owned by `app.orders`, `app.payments`, Stripe provider checkout-session
  creation, and `POST /api/stripe/webhook`.
- Checkout may create purchase/payment truth.
- Checkout must not write onboarding state.
- `session_id` is provider checkout-session correlation only and is not Aveli
  service/session domain authority.
- `client_secret`, `session_id`, and `order_id` do not grant membership,
  onboarding completion, routing, or app entry.

Membership authority:

- Owned by `app.memberships`.
- Purchase-backed membership changes only after backend webhook validation and
  persistence.
- Frontend success is not membership authority.

Onboarding authority:

- Owned by `app.auth_subjects.onboarding_state`.
- Create-profile and welcome are onboarding steps.
- Completion is explicit welcome confirmation only.

Profile projection boundary:

- `/profiles/me` is projection-only.
- `/profiles/me` must not become checkout, onboarding, or routing authority.

Routing authority:

- `GET /entry-state` owns routing outputs and precedence.

## 12. Trial Semantics

Current active contract truth:

- Ordinary purchase-backed membership checkout uses a 14-day trial/test
  period.
- Card details are required before the trial starts.
- Trial-backed checkout creates an order.
- Trial membership is `source = "purchase"`.
- Membership becomes active only after backend webhook confirms Stripe
  provider state and writes `app.memberships`.

Superseded rule:

- The 30-day ordinary self-signup checkout trial is no longer canonical.
- Any remaining runtime constant, task artifact, or frontend/backend behavior
  that preserves 30 days for ordinary purchase-backed membership checkout is
  implementation or derived-artifact drift.

## 13. Explicit Conflict Check

Conflict status: RESOLVED.

Decisions:

- `T14_membership_trial_duration_decision.md` ratifies the 14-day ordinary
  membership checkout trial/test period with card details required.
- `embedded_checkout_activation_decision.md` activates embedded Stripe
  checkout for ordinary purchase-backed membership checkout.
- Hosted or raw Stripe URL membership checkout is superseded and is not a
  canonical fallback.
- Course and bundle checkout remain on their current hosted checkout path.
- Service/session/Connect-like scope remains excluded from Baseline V2 launch
  authority unless later explicitly activated.

Stop implementation if an active contract still preserves 30 days, hosted/raw
Stripe URL membership checkout, or the legacy membership response shape as
canonical ordinary membership checkout truth.

Stop implementation if `session_id` is treated as Aveli service/session domain
authority or if provider session state is treated as Aveli domain authority.

## 14. Concrete Implementation Plan

This section is historical implementation-planning context until regenerated
after Baseline V2 authority freeze and production deployment authority
alignment are accepted.

1. Align backend membership checkout response to embedded Checkout:
   `client_secret`, `session_id`, `order_id`.
2. Stop using hosted Stripe URL as the primary ordinary membership checkout
   transport.
3. Apply the ratified 14-day trial/test period with required card details.
4. Keep order creation before Stripe session creation.
5. Keep webhook-only membership mutation.
6. Build Aveli checkout shell with Swedish copy and embedded Stripe payment.
7. Mobile WebView loads the Aveli shell, not raw Stripe-hosted checkout.
8. Frontend return state refreshes `GET /entry-state`.
9. Post-checkout routing goes to create-profile only through entry-state.
10. Add backend tests for trial/card/client-secret/webhook activation.
11. Add frontend tests for embedded shell, non-authority, and routing.

Final ordinary flow to verify after implementation:

`register -> checkout -> create-profile -> welcome -> onboarding-complete -> app`

Referral flow to preserve:

`register -> create-profile -> redeem -> welcome -> onboarding-complete -> app`

## 15. English Copy-Paste Implementation Prompts

This section is historical prompt context until regenerated after Baseline V2
authority freeze and production deployment authority alignment are accepted.
Generated operator prompts must be copy-paste-ready English.

Backend prompt:

```text
Implement the ratified Aveli embedded membership checkout backend flow. Update only membership checkout initiation and focused tests. Preserve app.orders and app.payments as purchase/payment authority, app.memberships as membership authority, Stripe webhook as the only membership mutation path, and app.auth_subjects as onboarding authority. Return an embedded checkout client_secret plus session_id and order_id. Apply the ratified trial duration and require card collection. Do not mutate /profiles/me authority or onboarding completion.
```

Frontend prompt:

```text
Implement the Aveli embedded membership checkout frontend shell. Use Swedish product copy, the Aveli logo, and a calm light-blue-to-purple visual direction. Mount Stripe embedded checkout only as a payment renderer. Do not grant app access, mutate membership, or treat Stripe success as authority. After checkout return, refresh GET /entry-state and route according to backend-owned entry state.
```

Test prompt:

```text
Add focused backend and frontend tests for the ratified embedded membership checkout flow. Cover trial duration, required card collection, embedded checkout response shape, webhook-only membership activation, frontend non-authority, checkout-before-create-profile precedence, create-profile to welcome, and welcome confirmation as the only onboarding completion trigger.
```

## 16. Stripe References

Primary Stripe references for later implementation:

- https://docs.stripe.com/api/checkout/sessions/create
- https://docs.stripe.com/payments/payment-element/migration-ewcs

Implementation must verify the exact `ui_mode`, return URL, and
`client_secret` parameters against the Stripe API version used by the repo at
implementation time.

## 17. Final Assertion

This spec is concrete for ordinary purchase-backed membership checkout at the
contract layer. Implementation planning remains blocked until the Baseline V2
authority-freeze batches and production deployment authority alignment are
accepted.

It preserves checkout/payment authority, membership authority, onboarding
authority, profile projection boundaries, backend webhook authority, and
`GET /entry-state` routing authority.

It does not authorize moving authority into `/profiles/me`, frontend
membership mutation, checkout-derived onboarding completion, app entry from
Stripe success alone, hosted/raw Stripe URL membership fallback, or moving
course and bundle checkout into embedded scope.

It does not authorize service/session/Connect-like scope. User-facing checkout
errors and product copy must be Swedish.
