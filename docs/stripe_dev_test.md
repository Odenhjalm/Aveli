# Stripe dev/test checklist

This guide describes how to keep the Stripe test environment stable while exercising the subscription checkout flow end to end.

## 1. Database prerequisites

- Critical migrations: `supabase/migrations/004_memberships_billing.sql`, `005_course_entitlements.sql`, and `006_course_pricing.sql`.
- Apply them to the active Supabase project before running the backend:
  - `cd backend && supabase db push` (recommended) **or**
  - `psql "$SUPABASE_DB_URL" < supabase/migrations/006_course_pricing.sql` (repeat for 004 + 005 if needed).
- If `app.memberships`, `app.payment_events`, or `app.billing_logs` are missing, rerun the migrations above before retesting.

## 2. Fill in test secrets

- Edit repo root `.env` **and** `backend/.env.local`.
- Replace the `sk_test_XXX`, `pk_test_XXX`, `price_XXX`, and `whsec_TEST_*` placeholders with the **test-mode** keys from the Stripe Dashboard.
- Always keep `STRIPE_CHECKOUT_UI_MODE=hosted`, `FRONTEND_BASE_URL=https://aveli.app`, and the deep links:
  - `CHECKOUT_SUCCESS_URL=aveliapp://checkout/success?checkout_success=true`
  - `CHECKOUT_CANCEL_URL=aveliapp://checkout/cancel`
- `STRIPE_WEBHOOK_SECRET` → `/webhooks/stripe` (Payment Element + one-off purchases).
- `STRIPE_BILLING_WEBHOOK_SECRET` → `/api/billing/webhook` (subscription + billing portal events).
- Set `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_YEARLY`, and any service/course `STRIPE_PRICE_*` entries to real test price IDs and note TODOs inline if something is pending.

## 3. Start the backend

```bash
cd backend
poetry install  # first time only
poetry run uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
```

Confirm `/healthz` and `/readyz` respond with HTTP 200 before moving on.

## 4. Forward webhooks locally

Run the Stripe CLI in another terminal to forward events into FastAPI:

```bash
stripe login  # once per machine
stripe listen --forward-to http://127.0.0.1:8080/webhooks/stripe
```

If you are testing `/api/billing/webhook`, start a second listener (or add `--forward-to` with that endpoint) using the billing webhook signing secret.

## 5. End-to-end test steps

1. Launch the dev app (mobile or web) pointing at `http://127.0.0.1:8080`.
2. Log in with a test user that does **not** yet have `app.memberships` data.
3. Tap **Starta medlemskap** to trigger `/api/checkout/create`.
4. Make sure the app launches Stripe Checkout (hosted), complete the session with the test card `4242 4242 4242 4242`.
5. Confirm the CLI prints webhook deliveries for `/webhooks/stripe` followed by `/api/billing/webhook`.
6. Check Supabase (SQL editor or `psql`) for the new row:
   ```sql
   select user_id, plan_interval, status, stripe_subscription_id
   from app.memberships
   where user_id = '<uuid>';
   ```
7. Hit `POST /api/billing/customer-portal`; it should return a Stripe portal URL once the membership row is active.
8. Refresh MySubscriptionPage inside the app — it should display “Aktiv” with the correct interval.
9. (Optional) Cancel via the Stripe dashboard, then rerun the test to ensure status updates propagate.

Keep the document updated whenever new price IDs or webhook endpoints are introduced so everyone can reproduce the flow quickly.

## Språk & texter (svenska)

- Stripe Checkout startas med `locale=sv` och appens betalnings-UI använder svenska etiketter som **“Köp paketet”**, **“Bli medlem”**, **“Betalning”** och felmeddelanden som **“Betalningen misslyckades. Försök igen eller kontakta support.”**
- Standard-redirects är `aveliapp://checkout_success` / `aveliapp://checkout_cancel` (eller `https://<FRONTEND_BASE_URL>/checkout/...` om frontend-basen är satt).
- Kontrollera att WebView stänger på både `aveliapp://checkout_*` och HTTPS-varianter och att entitlements uppdateras direkt efter lyckad betalning.

## Lärarpaket & betalningslänkar — hur man testar

1. Som lärare: gå till **Paketpriser** (`/teacher/bundles`) och skapa ett paket med pris i SEK, bocka för de kurser som ska ingå. Kopiera betalningslänken som genereras (`.../pay/bundle/<id>`).
2. Klistra in länken i en lektionsbeskrivning (Markdown). Appen ska rendera en tydlig CTA-knapp **“Köp paketet”** och öppna Stripe Checkout i WebView när du trycker.
3. Som student: tryck på länken/knappen, slutför betalningen i Stripe Checkout (testkort `4242...`). WebView ska stängas på success/cancel och entitlements ska uppdateras.
4. Verifiera i databasen: `app.course_entitlements` ska innehålla en rad per kurs i paketet och eventuella enrollment-poster ska vara skapade.
5. Avbryt-länkar ska fungera och stänga WebView utan att ge åtkomst. Kontrollera även att paket som markerats som inaktiva inte går att köpa (endpoint svarar 404/400).
