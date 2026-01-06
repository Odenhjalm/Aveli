# Environment Variables

## Backend (FastAPI)
- `APP_ENV` – environment name (`development`/`production`).
- `PORT` – listen port (default `8080`).
- `SUPABASE_URL` – project URL.
- `SUPABASE_ANON_KEY` – anon key (optional for backend, required for client paths).
- `SUPABASE_SERVICE_ROLE_KEY` – service role key (required for Storage/signing).
- `SUPABASE_DB_URL`/`DATABASE_URL` – Postgres URL (Supabase pooler).
- `SUPABASE_DB_PASSWORD` – Postgres password (used to build DB URL).
- `SUPABASE_JWT_SECRET` – Supabase JWT secret (tests/edge cases).
- `SUPABASE_PAT` – PAT for MCP helper (optional).
- `FRONTEND_BASE_URL` – base URL for checkout redirects.
- `STRIPE_RETURN_URL` – hosted checkout return URL (include `{CHECKOUT_SESSION_ID}`); mirror to `CHECKOUT_SUCCESS_URL`.
- `CHECKOUT_SUCCESS_URL` / `CHECKOUT_CANCEL_URL` – explicit override for Stripe success/cancel URLs.
- `STRIPE_SECRET_KEY` – secret API key.
- `STRIPE_PUBLISHABLE_KEY` – publishable key (exposed to Flutter).
- `STRIPE_WEBHOOK_SECRET` / `STRIPE_BILLING_WEBHOOK_SECRET` – webhook signing secrets.
- `STRIPE_CHECKOUT_UI_MODE` – `custom`/`hosted` (defaults to `custom`).
- `STRIPE_MERCHANT_DISPLAY_NAME` – label for Stripe receipts/SDK.
- `STRIPE_PRICE_MONTHLY` / `STRIPE_PRICE_YEARLY` – subscription prices.
- `STRIPE_PRICE_SERVICE_{SLUG}` – optional per-service price IDs.
- `STRIPE_CONNECT_CLIENT_ID` – Connect client ID (optional).
- `STRIPE_CONNECT_RETURN_URL` / `STRIPE_CONNECT_REFRESH_URL` – Connect onboarding redirects.
- `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` – LiveKit REST credentials.
- `LIVEKIT_WS_URL` / `LIVEKIT_API_URL` – WebSocket + REST endpoints.
- `LIVEKIT_WEBHOOK_SECRET` – webhook signing secret (optional).
- `JWT_SECRET` / `JWT_ALGORITHM` – backend auth signing config.
- `JWT_EXPIRES_MINUTES` / `JWT_REFRESH_EXPIRES_MINUTES` – auth TTLs.
- `MEDIA_SIGNING_SECRET` / `MEDIA_SIGNING_TTL_SECONDS` – media token signing.
- `MEDIA_PUBLIC_CACHE_SECONDS` – cache-control for signed uploads.
- `MEDIA_ALLOW_LEGACY_MEDIA` – allow legacy media paths (bool).
- `LESSON_MEDIA_MAX_BYTES` – max upload size (bytes).
- `CORS_ALLOW_ORIGINS` / `CORS_ALLOW_ORIGIN_REGEX` – CORS configuration.
- `QA_API_BASE_URL` / `QA_BASE_URL` – smoke test defaults.

## Flutter client (`frontend/.env`)
- `API_BASE_URL` – backend URL (use `http://10.0.2.2:8080` on Android emulators).
- `SUPABASE_URL` / `SUPABASE_ANON_KEY` – client Supabase credentials.
- `STRIPE_PUBLISHABLE_KEY` – publishable key for PaymentSheet.
- `STRIPE_MERCHANT_DISPLAY_NAME` – label for Stripe SDK.
- `SUBSCRIPTIONS_ENABLED` – toggles subscription UI (`true`/`false`).
- `IMAGE_LOGGING` – enables asset-load logging (`true`/`false`).

## Landing (Next.js) `frontend/landing`
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `NEXT_PUBLIC_API_BASE_URL` – backend URL (use service name `backend` in compose).
- `NEXT_PUBLIC_SENTRY_DSN` / `SENTRY_DSN` – optional monitoring.

## CI / Fly
- GitHub Actions reuses backend env above plus: `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_WS_URL`, `LIVEKIT_API_URL`, `MEDIA_SIGNING_SECRET`, `MEDIA_SIGNING_TTL_SECONDS`, `LESSON_MEDIA_MAX_BYTES`.
- Fly secrets should mirror the backend list; see `docs/DEPLOYMENT.md` for the `flyctl secrets set` command.
