# Observability

## Local MCP surfaces
- Mounted local HTTP MCP routes:
  - `GET/POST /mcp/logs`
  - `GET/POST /mcp/media-control-plane`
  - `GET/POST /mcp/verification`
  - `GET/POST /mcp/domain-observability`
- These routes are local-only and enforce local client/origin checks in the FastAPI app.
- `.vscode/mcp.json` also includes repo-side helpers such as `aveli_semantic_search`, but the mounted backend observability contract is the four HTTP routes above.

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
1. Flutter klienten initierar en betalning och skickar `POST /api/checkout/create` med `request_id` header.
2. FastAPI loggar order/status i JSON med `request_id`, `user_id`, `route="/api/checkout/create"`, samtidigt som Sentry trace samlas in.
3. Vid lesson media-uppladdning begär klienten `POST /api/media/upload-url`, laddar upp bytes direkt till returnerad `upload_url`, och slutför sedan med `POST /api/media/complete` följt av `POST /api/media/attach`.
4. Den direkta storage-uppladdningen korreleras tillbaka via `storage.objects`-kontroller och media-pipeline state i backendens loggar och MCP-surfacer.
5. Stripe webhooken träffar `/stripe/webhook`; med hjälp av samma `request_id` kan backend-loggarna parsas tillsammans med Flutter/Sentry-event och övriga observability-signaler.

## VERIFIED_TASK verification
- VERIFIED_TASK pre-check/post-check behavior is driven by task instructions and operator workflow.
- The mounted MCP routes provide evidence for those checks, but they do not implement a global automatic execution gate for every mutation.

## DSN-hantering
- Lokal utveckling: lämna `SENTRY_DSN` blank → Sentry initieras inte men loggarna fortsätter.
- CI/Prod: injicera `BACKEND_SENTRY_DSN` och `FRONTEND_SENTRY_DSN` via GitHub Actions och `.env.ci.*` mallarna.
