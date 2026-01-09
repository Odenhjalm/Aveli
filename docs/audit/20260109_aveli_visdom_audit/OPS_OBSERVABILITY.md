# Ops + Observability (Phase 5)

## Logging
- Structured JSON logging is configured in `backend/app/logging_utils.py` (root logger with JSON formatter).
- Request IDs are created in `backend/app/middleware/request_context.py` and returned as `X-Request-ID` response header.
- The `RequestContextFilter` in `backend/app/logging_context.py` is not wired into the logger config, so request_id/user_id are not injected by default into log records.
- Several routes manually log with `request_id` (e.g. `backend/app/routes/api_ai.py`, `backend/app/routes/api_context7.py`).

## Sentry / error capture
- Backend initializes Sentry in `backend/app/main.py` with FastAPI + Starlette integrations, gated by `settings.sentry_dsn`.
- Stripe + LiveKit webhook handlers capture events explicitly in `backend/app/routes/stripe_webhooks.py` and `backend/app/services/livekit_events.py`.
- Landing (Next.js) initializes Sentry in `frontend/landing/sentry.client.config.ts` and `frontend/landing/sentry.server.config.ts` using `NEXT_PUBLIC_SENTRY_DSN`/`SENTRY_DSN`.
- Flutter uses Firebase Crashlytics wrappers in `frontend/lib/domain/services/analytics_service.dart`, but Firebase options are placeholders in `frontend/lib/firebase_options.dart` and there is no `Firebase.initializeApp` call in code.

## Metrics
- `/metrics` endpoint is exposed in `backend/app/main.py` with Prometheus client optional import.
- LiveKit worker metrics (queue size, retries, processed/failed totals) are defined in `backend/app/metrics.py` and updated in `backend/app/services/livekit_events.py`.

## Performance and throughput
- Media streaming supports HTTP range requests in `backend/app/routes/media.py` and sets cache headers based on `media_signing_ttl_seconds` in `backend/app/config.py`.
- Media caching on client: `frontend/lib/features/media/data/media_repository.dart` caches downloaded media on disk (non-web) and in-memory (web).
- Stripe checkout creation invokes external Stripe API during request handling in `backend/app/services/checkout_service.py` and `backend/app/services/subscription_service.py`.

## Rate limiting / abuse
- Login rate limiting exists only in `backend/app/routes/auth.py`, which is not mounted in `backend/app/main.py`.
- No global or per-endpoint rate limiting is configured for mounted routes.

## Quick wins
- Attach `RequestContextFilter` in `backend/app/logging_utils.py` so request_id/user_id are always present in JSON logs.
- Set user context on every authenticated request (call `set_user_context` in auth dependency) to improve log + Sentry correlation.
- Add rate limiting to auth and webhook endpoints; mirror to `/auth/*` routes actually mounted (`backend/app/routes/api_auth.py`).
- Consider tracing for Stripe/LiveKit webhook flows (store request_id in webhook job table and log it on retries).
