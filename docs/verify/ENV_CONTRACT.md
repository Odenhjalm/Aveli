# Environment Contract

## Sources of truth
- Backend env loader: `backend/app/config.py` (Pydantic BaseSettings) reads `.env` and `../.env` for local runs.
- DB connection: `backend/app/db.py` uses `settings.database_url` (defaults to `SUPABASE_DB_URL`).
- Tests: `backend/tests/conftest.py` imports `app.config`, so test env uses the same loader.
- Flutter: `frontend/lib/core/env/env_resolver.dart` prefers `--dart-define` and falls back to dotenv in non-release builds.
- Flutter dotenv: `frontend/lib/main.dart` loads the file named by `DOTENV_FILE` (non-web only).
- Landing (Next.js): `frontend/landing` reads `process.env` at build/runtime (Sentry only).
- Migrations: canonical SQL lives in `supabase/migrations` and is applied by `backend/scripts/apply_supabase_migrations.sh`.

## Backend (FastAPI) env vars
Set via local `.env`, Fly secrets, or CI secrets.
- Core: `APP_ENV`, `PORT`, `FRONTEND_BASE_URL`, `CORS_ALLOW_ORIGINS`, `CORS_ALLOW_ORIGIN_REGEX`
- Supabase: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL`, `DATABASE_URL`, `SUPABASE_DB_PASSWORD`, `SUPABASE_JWT_SECRET`, `SUPABASE_PROJECT_REF`, `SUPABASE_PAT`
- Auth/media: `JWT_SECRET`, `JWT_ALGORITHM`, `JWT_EXPIRES_MINUTES`, `JWT_REFRESH_EXPIRES_MINUTES`, `MEDIA_SIGNING_SECRET`, `MEDIA_SIGNING_TTL_SECONDS`, `MEDIA_ROOT`, `MEDIA_PUBLIC_CACHE_SECONDS`, `MEDIA_ALLOW_LEGACY_MEDIA`, `LESSON_MEDIA_MAX_BYTES`
- Stripe: `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_BILLING_WEBHOOK_SECRET`, `STRIPE_CHECKOUT_UI_MODE`, `STRIPE_MERCHANT_DISPLAY_NAME`, `STRIPE_CONNECT_CLIENT_ID`, `STRIPE_CONNECT_RETURN_URL`, `STRIPE_CONNECT_REFRESH_URL`, `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_YEARLY`, `STRIPE_PRICE_SERVICE_{SLUG}`, `CHECKOUT_SUCCESS_URL`, `CHECKOUT_CANCEL_URL`
- LiveKit: `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_API_URL`, `LIVEKIT_WS_URL`, `LIVEKIT_WEBHOOK_SECRET`
- QA: `QA_API_BASE_URL`, `QA_BASE_URL`

Notes:
- `/webhooks/stripe` uses `STRIPE_WEBHOOK_SECRET`.
- `/api/billing/webhook` uses `STRIPE_BILLING_WEBHOOK_SECRET` (falls back to `STRIPE_WEBHOOK_SECRET`).

## Flutter client env vars
Set via `--dart-define` (web/CI) or `frontend/.env` with `DOTENV_FILE` (local non-web).
- API: `API_BASE_URL`
- Supabase: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_API_KEY` (alias: `SUPABASE_ANON_KEY`)
- Stripe (publishable only): `STRIPE_PUBLISHABLE_KEY`, `STRIPE_MERCHANT_DISPLAY_NAME`
- OAuth: `OAUTH_REDIRECT_WEB`, `OAUTH_REDIRECT_MOBILE`
- Optional: `FRONTEND_URL`, `SUBSCRIPTIONS_ENABLED`, `IMAGE_LOGGING`

## Landing (Next.js) env vars
Set via `.env`, `.env.local`, or hosting provider build env.
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `NEXT_PUBLIC_API_BASE_URL`
- `NEXT_PUBLIC_SENTRY_DSN`, `SENTRY_DSN`

## Ops/verification env vars
Used by scripts in `ops/`.
- Guardrails: `ENVIRONMENT`, `CONFIRM_NON_PROD`
- Supabase project allowlist: `SUPABASE_PROJECT_REF` must exist in `docs/ops/SUPABASE_ALLOWLIST.txt` for remote checks.
- CI behavior: `CI` (env validation fails in CI, warns locally)
- Tests: `REQUIRE_DB_TESTS`
