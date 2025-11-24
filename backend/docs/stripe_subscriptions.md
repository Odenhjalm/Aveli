# Stripe Billing Subscriptions

AVELI sells fixed-price memberships through Stripe Billing. The backend issues Checkout Sessions in `ui_mode="custom"` and the frontend renders Stripe's Payment Element so members can pay inside the app. Stripe webhooks notify the backend so Supabase mirrors every subscription lifecycle change.

## Integration Overview
- **Fixed-price memberships**: each tier such as "Member Basic" or "Teacher Pro" is a Stripe Product with at least one recurring Price (monthly, yearly, etc.).
- **Checkout Sessions + Payment Element**: FastAPI creates Checkout Sessions in custom UI mode, Flutter/Web consumes the returned `client_secret` and mounts the Payment Element for a native checkout experience.
- **Webhook-driven sync**: Stripe events (`customer.subscription.*`, optionally `checkout.session.completed`) hit our `/api/stripe/webhook`. Handlers update Supabase so entitlements stay aligned with billing state.

## Getting the Required Stripe Values
1. **Sign in to Stripe Dashboard**
   - Visit [dashboard.stripe.com](https://dashboard.stripe.com) and toggle **Test mode** while developing.
2. **API keys**
   - Navigate to **Developers → API keys**.
   - Copy the **Secret key** (`sk_test_…`/`sk_live_…`) → add to `.env` as `STRIPE_SECRET_KEY`.
   - Copy the **Publishable key** (`pk_test_…`) → add to `.env` as `STRIPE_PUBLISHABLE_KEY`.
3. **Products and recurring prices**
   - Go to **Billing → Products → Add product**.
   - For every membership tier, create a Product and attach recurring Prices (monthly, yearly, etc.).
   - Record each **Price ID** (`price_…`) and **Product ID** (`prod_…`) so code can map plan codes to Stripe resources.
4. **Webhook endpoint**
   - **Development**: install Stripe CLI, run `stripe login`, then `stripe listen --forward-to localhost:8000/api/stripe/webhook`. Copy the printed signing secret (`whsec_…`).
   - **Production**:
     - Navigate to **Developers → Webhooks → Add endpoint**.
     - URL: `https://YOUR_BACKEND_DOMAIN/api/stripe/webhook`.
     - Events to receive: `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, and optionally `checkout.session.completed`.
     - Copy the signing secret → store as `STRIPE_WEBHOOK_SECRET`.
5. **Store everything securely**
   - Place all keys, price IDs, and webhook secrets in your local `.env`. Never commit actual values—share them only via a secure secret manager.

## Supabase Subscription Mirror (`app.subscriptions`)
Stripe stays the billing source of truth, while Supabase keeps a projection used by the app. The table should capture at least:

- `user_id uuid` – Supabase Auth user id (`app.profiles.user_id`) the subscription belongs to.
- `stripe_customer_id text` – `cus_…` id for the Stripe customer.
- `stripe_subscription_id text` – `sub_…` id for the active subscription.
- `stripe_price_id text` – `price_…` id tied to the plan.
- `stripe_product_id text` – `prod_…` id backing the price.
- `plan_code text` – internal string like `member_basic` for entitlement logic.
- `status text` – Stripe status (`trialing`, `active`, `past_due`, `canceled`, etc.).
- `period_start timestamptz` / `period_end timestamptz` – current billing window.
- `cancel_at timestamptz` / `cancel_at_period_end boolean` – when cancellation takes effect.

Webhook handlers upsert this table on every relevant event so Flutter/Web can immediately reflect membership access and enforce RLS policies.
