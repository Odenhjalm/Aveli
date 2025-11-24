# Backend (FastAPI + Supabase)

FastAPI backend backed by Supabase Postgres/Storage. Stripe handles payments/billing; LiveKit handles SFU/webinars. All tables and RLS live in `supabase/migrations`.

## Environment
Load from `.env` (root) or `.env.docker` when using compose:

- `SUPABASE_DB_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`
- `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_BILLING_WEBHOOK_SECRET`, `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_YEARLY`
- `JWT_SECRET`, `MEDIA_SIGNING_SECRET`
- `LIVEKIT_*` (API key/secret/url/ws)

`backend/app/config.py` now *requires* Supabase URLs/keys; `DATABASE_URL` defaults to `SUPABASE_DB_URL`.

## Run locally
```
poetry install --no-root
poetry run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```
- `/healthz` basic; `/readyz` checks DB connectivity.
- `/metrics` available if `prometheus_client` is installed.

## Tests
```
make backend.test   # pytest
make backend.lint   # ruff
```
New test covers `/readyz` DB failure handling.

## QA
```
make qa.teacher    # auth -> list services -> order -> Stripe session -> membership
```
Requires a running backend and valid Stripe/Supabase keys.

## Supabase migrations
```
SUPABASE_DB_URL=... SUPABASE_DB_PASSWORD=... scripts/apply_supabase_migrations.sh
```
Use MCP for interactive SQL, then add/adjust migrations under `supabase/migrations/`.

## Key modules
- `app/main.py` – app wiring, routers, CORS, metrics
- `app/config.py` – Pydantic settings (Supabase-first)
- `app/services/` – Stripe checkout/billing, LiveKit, storage
- `app/repositories/` – SQL access per domain (courses, sessions, memberships, etc.)

CI runs migrations → pytest → QA smoke → `flutter test` (see `.github/workflows/flutter.yml`).
