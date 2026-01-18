# Backend (FastAPI + Supabase)

FastAPI API backed by Supabase Postgres/Storage. Stripe powers payments/subscriptions/Connect; LiveKit handles SFU/webinars. All schema/RLS lives in `supabase/migrations`.

## Environment
Load from `.env.backend` or `.env` (see `docs/ENV_VARS.md`):
- Supabase: `SUPABASE_URL`, `SUPABASE_SECRET_API_KEY` (legacy: `SUPABASE_SERVICE_ROLE_KEY`), `SUPABASE_PUBLISHABLE_API_KEY` (legacy: `SUPABASE_ANON_KEY`), `SUPABASE_DB_URL`
- Stripe: `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_BILLING_WEBHOOK_SECRET`, `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_YEARLY`, `STRIPE_PRICE_SERVICE_*`
- LiveKit: `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_WS_URL`, `LIVEKIT_API_URL`, `LIVEKIT_WEBHOOK_SECRET`
- Auth/media: `JWT_SECRET`, `MEDIA_SIGNING_SECRET`, `MEDIA_SIGNING_TTL_SECONDS`, `LESSON_MEDIA_MAX_BYTES`
- Checkout redirects: `FRONTEND_BASE_URL`, `CHECKOUT_SUCCESS_URL`, `CHECKOUT_CANCEL_URL`

Default port: `8080`.

## Run locally
```bash
poetry install --no-interaction
PORT=8080 poetry run uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
```
- `/healthz` basic; `/readyz` checks DB connectivity.
- `/metrics` available if `prometheus_client` is installed.

## Tests
```bash
make backend.test   # pytest
make backend.lint   # ruff
```
Smoke:
```bash
make qa.teacher  # requires running backend + secrets
```

## Supabase migrations
```bash
SUPABASE_DB_URL=postgres://... \
SUPABASE_DB_PASSWORD=... \
scripts/apply_supabase_migrations.sh
```
Source of truth: `supabase/migrations/*.sql`. Use MCP for interactive SQL, then commit a migration.

## Key modules
- `app/main.py` – app wiring, routers, CORS, health/metrics
- `app/config.py` – settings for Supabase, Stripe, LiveKit, auth/media
- `app/services/` – Stripe checkout/billing, LiveKit, storage
- `app/repositories/` – DB access per domain (courses, sessions, memberships, etc.)
- `app/routes/` – API endpoints (`/auth`, `/payments`, `/sfu`, `/webhooks/stripe`, etc.)
