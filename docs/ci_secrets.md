# CI Secrets & Environment Templates

## Backend CI (`.github/workflows/backend-ci.yml`)
- Required secrets: `BACKEND_DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_SECRET_API_KEY`, `SUPABASE_PUBLISHABLE_API_KEY` (legacy aliases: `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_PUBLIC_API_KEY`), `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_BILLING_WEBHOOK_SECRET`, `STRIPE_MEMBERSHIP_PRODUCT_ID`, `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_YEARLY`, `FRONTEND_BASE_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_API_URL`, `LIVEKIT_WS_URL`, `MEDIA_SIGNING_SECRET`, `MEDIA_SIGNING_TTL_SECONDS`, `JWT_SECRET`, `BACKEND_SENTRY_DSN`.
- Workflow exports those secrets at job-level and renders `backend/.env` via `envsubst < ../.env.ci.backend > .env`.
- Keep `.env.ci.backend` in sync with `app.config.Settings` so linters/tests run with full config.

## Flutter CI (`.github/workflows/flutter.yml`)
- Secrets: `FRONTEND_API_BASE_URL`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_MERCHANT_DISPLAY_NAME`, `SUBSCRIPTIONS_ENABLED`, `IMAGE_LOGGING`, `FRONTEND_SENTRY_DSN`.
- Step `Prepare frontend env` builds `.env` from `.env.ci.frontend` before running `flutter pub get`, `analyze`, and tests.
- Same template is reused for `release-android.yml`.

## Release Android (`.github/workflows/release-android.yml`)
- Uses the identical secret set as Flutter CI for deterministic builds.
- Ensure `FRONTEND_SENTRY_DSN` exists even if empty; `envsubst` writes an empty string when the secret is unset.

## QA Smoke job (Flutter workflow)
- Continues to rely on dedicated `QA_*` secrets plus `QA_DATABASE_URL` for provisioning Postgres.
- No `.env` rendering is required because the smoke tests call the deployed backend via HTTP.

## Template usage
- `.env.ci.backend` and `.env.ci.frontend` only contain `${VAR}` placeholders. GitHub Actions jobs must export the referenced variables before running `envsubst`.
- Never commit real secrets; rotate GitHub Secrets whenever changing the template structure.
