# Audit Existing Checkout And Stripe Surfaces

## Status

NO-CODE AUDIT.

This file captures repo evidence for checkout, Stripe, billing,
subscriptions, trials, payment-session handling, webhooks, membership mutation,
frontend routing, and stale embedded-payment residue. It authorizes no backend,
frontend, baseline, test, or active-contract implementation change.

## Authority Inputs

- `actual_truth/contracts/onboarding_target_truth_decision.md`
- `actual_truth/contracts/application_domain_map_contract.md`
- `actual_truth/contracts/commerce_membership_contract.md`
- `actual_truth/contracts/onboarding_contract.md`
- `actual_truth/contracts/onboarding_entry_authority_contract.md`
- `actual_truth/contracts/task_tree_execution_controller_contract.md`
- `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/`
- current repo state in `backend/`, `frontend/`, and baseline slots

## Current-State Summary

The repo has backend-authoritative Stripe Checkout infrastructure, not a fully
Aveli-hosted embedded checkout implementation.

Current checkout shape:

1. Frontend calls backend to create a checkout session.
2. Backend creates a pending order in `app.orders`.
3. Backend creates a Stripe Checkout Session.
4. Frontend opens the returned Stripe URL in an in-app WebView where supported.
5. Stripe webhook is the canonical completion path.
6. Backend webhook handling updates `app.orders`, records `app.payments`, and
   updates `app.memberships` or course access when relevant.
7. Frontend success/cancel handling refreshes backend state and does not grant
   access locally.

Current trial/card state:

- `backend/app/services/subscription_service.py` defines
  `ORDINARY_MEMBERSHIP_TRIAL_DAYS = 30`.
- Membership checkout sends `payment_method_collection = "always"`.
- Membership checkout sends `subscription_data.trial_period_days = 30`.

Conflict:

- Active contract truth still says ordinary self-signup checkout has a 30-day
  free trial with card details required.
- The newly declared product intent says the user gets 14 days to test the app.
- This is a product-rule conflict requiring ratification before implementation.

## Backend Surfaces Found

### Membership Checkout

Evidence:

- `backend/app/routes/billing.py`
- `backend/app/schemas/billing.py`
- `backend/app/services/subscription_service.py`
- `backend/tests/test_create_subscription_session.py`

Current behavior:

- Mounted route: `POST /api/billing/create-subscription`.
- Request shape: `{ "interval": "month" | "year" }`.
- Response shape: `{ "url": string, "session_id": string, "order_id": string }`.
- Requires authenticated `CurrentUser`.
- Creates pending `app.orders` row with `order_type = "subscription"`.
- Resolves Stripe price through `stripe_mode.resolve_membership_price`.
- Ensures Stripe customer through `app.stripe_customers`.
- Creates Stripe Checkout Session with `mode = "subscription"`.
- Stores `checkout_type = "membership"`, `source = "purchase"`,
  `user_id`, `interval`, `price_id`, and `order_id` in metadata.
- Returns a Stripe URL for hosted/WebView-style payment.

Partial implementation:

- 30-day trial is currently wired in code.
- Card collection is currently forced with `payment_method_collection =
  "always"`.
- Stripe `trialing` subscriptions are treated as active purchase-backed
  membership in backend webhook handling.

Missing for embedded checkout:

- No `client_secret` response field.
- No Aveli-hosted embedded checkout shell.
- No tests asserting trial/card parameters.

### Course Checkout

Evidence:

- `backend/app/routes/api_checkout.py`
- `backend/app/services/checkout_service.py`
- `backend/app/schemas/checkout.py`
- `backend/tests/test_course_checkout.py`

Current behavior:

- Mounted route: `POST /api/checkout/create`.
- Active route accepts only `{ "slug": string }`.
- Active route rejects legacy/polymorphic bodies.
- Creates order/payment substrate for course purchases.
- Creates Stripe Checkout Session in `mode = "payment"`.
- Returns `{ "url", "session_id", "order_id" }`.

Stale residue:

- `backend/app/schemas/checkout.py` still defines a polymorphic
  `CheckoutCreateRequest`, but the mounted route rejects that body shape.
- `checkout_service.py` passes `ui_mode = settings.stripe_checkout_ui_mode or
  "custom"` while still expecting `session.url`. This mixes embedded/custom
  checkout residue with hosted URL assumptions.

### Bundle Checkout

Evidence:

- `backend/app/routes/course_bundles.py`
- `backend/app/services/course_bundles_service.py`
- `frontend/lib/features/teacher/data/course_bundles_repository.dart`
- `frontend/lib/features/teacher/presentation/course_bundle_page.dart`

Current behavior:

- Mounted route: `POST /api/course-bundles/{bundle_id}/checkout-session`.
- Frontend opens the returned backend-created checkout URL through the common
  checkout route.

Stale residue:

- Bundle checkout shares the same `ui_mode` plus URL-return mismatch as course
  checkout.

### Stripe Webhook

Evidence:

- `backend/app/routes/stripe_webhooks.py`
- `backend/app/services/stripe_webhook_membership_service.py`
- `backend/app/services/subscription_service.py`
- `backend/app/services/stripe_webhook_course_service.py`
- `backend/app/services/stripe_webhook_bundle_service.py`
- `backend/app/services/stripe_webhook_support_service.py`
- `backend/tests/test_webhook_upsert.py`
- `backend/tests/test_webhook_support_tables_contract.py`

Current behavior:

- Mounted route: `POST /api/stripe/webhook`.
- Validates Stripe signature.
- Uses `app.payment_events` for idempotency/claiming.
- Dispatches membership checkout/session/subscription/invoice events to
  membership handling.
- Dispatches course and bundle checkout completions to fulfillment services.
- Records payments in `app.payments`.
- Updates orders in `app.orders`.
- Updates `app.memberships` only from backend webhook handling.

Supported membership event types include:

- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `invoice.payment_succeeded`
- `invoice.payment_failed`

## Baseline Surfaces Found

Evidence:

- `backend/supabase/baseline_slots/0013_memberships_core.sql`
- `backend/supabase/baseline_slots/0026_canonical_app_memberships_authority.sql`
- `backend/supabase/baseline_slots/0029_canonical_purchase_substrate_foundation.sql`
- `backend/supabase/baseline_slots/0032_memberships_fail_closed_constraints.sql`
- `backend/supabase/baseline_slots/0034_payment_events_webhook_idempotency_support.sql`
- `backend/supabase/baseline_slots/0036_restore_billing_logs.sql`
- `backend/supabase/baseline_slots/0037_memberships_referral_source_alignment.sql`

Current baseline support:

- `app.memberships` is the current membership authority.
- `app.orders` is purchase identity/lifecycle substrate.
- `app.payments` is payment settlement substrate.
- `app.stripe_customers` maps app users to Stripe customers.
- `app.payment_events` supports webhook idempotency.
- `app.billing_logs` supports billing observability.
- Membership source vocabulary is aligned to `purchase`, `referral`, and
  `coupon`.

Missing:

- No embedded-checkout client-secret storage exists.
- No dedicated embedded-checkout support table exists.
- A simple embedded architecture can avoid a new table by returning the
  short-lived Stripe Checkout Session `client_secret` in the authenticated
  create-session response.

## Frontend Surfaces Found

### Routing

Evidence:

- `frontend/lib/core/routing/app_router.dart`
- `frontend/lib/core/routing/route_paths.dart`
- `frontend/lib/core/routing/route_session.dart`
- `frontend/lib/core/routing/route_manifest.dart`
- `frontend/test/routing/app_router_test.dart`

Current behavior:

- `needsPayment` routes to `/subscribe`.
- `/checkout/web` opens the checkout WebView route.
- `/success` and `/cancel` are checkout result routes.
- Checkout success/cancel routes are public.
- Checkout routes are treated as pre-entry surfaces.
- Router code already includes `welcome_pending` and referral
  `create-profile` exception logic.

Drift:

- The ordinary target says `checkout`; the mounted start route remains
  `/subscribe`.
- Some tests still carry stale wording or expectations around onboarding
  routing versus `welcome_pending`.

### Subscribe And Checkout UI

Evidence:

- `frontend/lib/features/payments/presentation/subscribe_screen.dart`
- `frontend/lib/features/paywall/data/checkout_api.dart`
- `frontend/lib/features/paywall/application/checkout_flow.dart`
- `frontend/lib/features/paywall/presentation/checkout_webview_page.dart`
- `frontend/lib/features/paywall/presentation/checkout_result_page.dart`
- `frontend/lib/core/deeplinks/deep_link_service.dart`

Current behavior:

- `SubscribeScreen` calls `CheckoutApi.createMembershipCheckout`.
- `CheckoutApi` calls `/api/billing/create-subscription`.
- Returned URL is pushed to `AppRoute.checkout`.
- `CheckoutWebViewPage` loads the URL in WebView on supported mobile platforms.
- Web/Windows/Linux currently show an unavailable embedded-payment message.
- Success/cancel redirects refresh backend session state.
- Frontend success state does not grant membership or app entry.

Missing:

- No Aveli-branded embedded checkout shell.
- No Stripe embedded checkout client-secret flow.
- No visible 14-day trial copy.
- No explicit card-required copy.
- No membership-includes copy block.

### Payment SDK Residue

Evidence:

- `frontend/lib/domain/services/payments/payments_stripe.dart`
- `frontend/lib/domain/services/payments/payments_fake.dart`
- `frontend/pubspec.yaml`
- `actual_truth/DETERMINED_TASKS/checkout_onboarding_payment_surface/COP-007_unused_payment_and_supabase_sdk_residue_isolation.md`
- `actual_truth/DETERMINED_TASKS/checkout_onboarding_payment_surface/COP-012_frontend_stripe_env_native_residue_cleanup.md`

Current state:

- `payments_stripe.dart` and `payments_fake.dart` are empty residue files.
- `frontend/pubspec.yaml` does not include `flutter_stripe`.
- `frontend/pubspec.yaml` includes WebView packages.
- Existing checkout task docs previously classified frontend Stripe SDK/native
  residue as cleanup scope.

Embedded-checkout implication:

- True embedded Stripe Checkout requires Stripe.js and a publishable key in the
  rendering surface.
- To keep Flutter app code simple and non-authoritative, the recommended path
  is an Aveli-hosted web checkout shell loaded by the existing WebView route.

## Test Surfaces Found

Existing coverage:

- Membership checkout calls backend subscription endpoint.
- Course checkout calls backend course checkout endpoint.
- Bundle checkout calls backend bundle endpoint.
- Checkout result and deep link handling refresh backend state.
- Frontend checkout tests forbid direct Stripe/Supabase authority.
- Webhook membership upsert and idempotency are tested.
- Course checkout webhook fulfillment is tested.
- Payment surfaces are tested not to mutate onboarding or return app-entry.

Missing coverage:

- No embedded checkout response-shape test.
- No client-secret handling test.
- No Aveli checkout shell test.
- No trial duration test for 14 days because active truth remains 30.
- No card collection assertion in membership checkout test.
- No complete ordinary flow test from register through checkout, create-profile,
  welcome confirmation, and app entry.

## Explicit Conflict Check

Conflict status: REQUIRES RATIFICATION.

- Current locked target truth: 30-day free trial with card details required.
- Newly declared product intent: 14 days to test the app with card details
  required.
- This audit does not override current 30-day contract truth.
- Implementation must not change trial duration until the contract stack and
  onboarding task tree are ratified.

## Review Decision

Proceed with a draft embedded-checkout specification only.

The paired spec may describe the intended 14-day product copy, but it must mark
that rule as pending ratification and must not claim the repo already enforces
14 days.

## Verification

- Audit is grounded in repo evidence listed above.
- No code changes are authorized by this audit.
- No baseline changes are authorized by this audit.
- No active contract rewrites are authorized by this audit.
- `/profiles/me` remains projection-only.
- Checkout/payment authority remains separate from onboarding authority.
- Produced user-facing checkout copy in the paired spec is Swedish.
- Produced developer prompts in the paired spec are English and copy-paste
  ready.
