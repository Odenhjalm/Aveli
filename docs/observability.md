# Observability

## Sentry
- **Backend**: Configure `SENTRY_DSN` and `APP_ENV` in environment variables. `app.config.Settings` feeds `sentry_sdk.init(...)` with `FastApiIntegration` and `traces_sample_rate`.
- **Flutter**: `.env` exposes `SENTRY_DSN`; `main.dart` loads it and boots the app through `SentryFlutter.init`. Errors from `FlutterError.onError`, `PlatformDispatcher.onError`, and the `runZonedGuarded` boundary call `Sentry.captureException`.
- **Next.js**: `@sentry/nextjs` is initialised in `sentry.client.config.ts` / `sentry.server.config.ts`. `NEXT_PUBLIC_SENTRY_DSN` mirrors `SENTRY_DSN` for browser bundles.

## Loggformat och korrelation
- `logging_utils.JSONFormatter` renders one JSON object per line with message, level, and timestamp.
- `RequestContextMiddleware` injects a `request_id` (from `X-Request-ID` or generated UUID) into a `ContextVar`. `auth.get_current_user` writes `user_id` to the same context.
- All log handlers attach the `RequestContextFilter`, so every record includes `{ "request_id": "...", "user_id": "..." }` under the `context` key.
- The middleware mirrors `request_id` back to the HTTP response header and Sentry scope.

## Flowexempel – Stripe → Backend → Supabase
1. Flutter klienten initierar en betalning och skickar `POST /checkout/session` med `request_id` header.
2. FastAPI loggar order/status i JSON med `request_id`, `user_id`, `route="/checkout/session"`, samtidigt som Sentry trace samlas in.
3. Vid mediauppladdning begär klienten `/media/presign` → logg `{"message":"storage presign","context":{"request_id":...}}` + Sentry breadcrumb.
4. Klienten laddar upp direkt till Supabase med signerad URL; eventet kopplas tillbaka via `storage.objects` webhook → FastAPI loggar `user_id` för RLS-debuggning.
5. Stripe webhooken träffar `/stripe/webhook`; med hjälp av samma `request_id` kan backend-loggarna parsas tillsammans med Flutter/Sentry eventet och Supabase Storage loggar.

## DSN-hantering
- Lokal utveckling: lämna `SENTRY_DSN` blank → Sentry initieras inte men loggarna fortsätter.
- CI/Prod: injicera `BACKEND_SENTRY_DSN` och `FRONTEND_SENTRY_DSN` via GitHub Actions och `.env.ci.*` mallarna.
