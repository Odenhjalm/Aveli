# Aveli/Visdom Audit - 20260109

## Executive Summary
- Current state: Backend + DB schema are extensive and the core product flows (auth, courses, seminars, billing) exist in code, but there are frontend/backend contract mismatches and auth/observability gaps that will surface as runtime failures.
- Stable areas:
  - Flutter unit/widget tests pass (`flutter test`).
  - Landing site tests and lint pass (`npm test`, `npm run lint`).
  - Core API surface is implemented (177 endpoints in `docs/audit/20260109_aveli_visdom_audit/API_CATALOG.md`).
- Highest risk areas:
  - Payment route accounting drift: mounted purchase flows live under `/api/checkout/*`, `/api/billing/*`, and `/orders`, while legacy `/payments/*` and `/checkout/session` claims remain historical-only and must not be treated as current runtime truth.
  - Auth audit drift: `backend/app/routes/auth.py` still exists in the repo, but mounted auth truth lives in `backend/app/routes/api_auth.py` plus `backend/app/routes/email_verification.py`, and audit artifacts must treat the duplicate file as legacy-only.
  - RLS: `app.course_entitlements` is missing RLS and feed policy is permissive.
  - Flutter static analysis fails due to missing `package:aveli/*` imports, which would fail CI/build.

Launch blockers (must fix before launch): endpoint mismatches, unmounted routes, RLS gaps, and broken Flutter analysis. Post-launch improvements: observability correlation, rate limiting, and expanded testing.

## Prioritized Action Plan

### P0-1: Reclassify legacy payments router drift
What: January audit notes still treat `/payments/*` and `/checkout/session` as if they define current purchase/runtime truth, but mounted payment behavior comes from `backend/app/routes/api_checkout.py`, `backend/app/routes/billing.py`, and `backend/app/routes/api_orders.py`.
Where: `backend/app/main.py`, `backend/app/routes/api_checkout.py`, `backend/app/routes/billing.py`, `backend/app/routes/api_orders.py`, `backend/app/routes/api_payments.py`, `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md`.
Why: Audit consumers can misclassify unmounted or stale endpoints as active runtime truth even though the canonical handlers are already mounted elsewhere.
Risk: Incorrect route accounting, misleading payment remediation plans, and duplicate `/payments/*` logic being treated as current.
Fix: Keep `POST /api/checkout/create`, `POST /api/billing/create-subscription`, `POST /api/billing/customer-portal`, `POST /orders`, and `GET /orders/{order_id}` as the canonical mounted inventory. Treat `backend/app/routes/api_payments.py` as legacy-only because `backend/app/main.py` does not mount it.
Test: Verify `backend/app/main.py` includes `api_checkout.router`, `billing.router`, and `api_orders.router` but does not include `api_payments.router`, then verify audit docs no longer describe legacy `/payments/*` paths as active runtime truth.

### P0-2: Reclassify legacy auth router drift
What: January audit notes still treat `backend/app/routes/auth.py` as if it defines current password-reset truth, but the mounted auth runtime comes from `backend/app/routes/api_auth.py` and mounted verification-email flows come from `backend/app/routes/email_verification.py`.
Where: `backend/app/main.py`, `backend/app/routes/api_auth.py`, `backend/app/routes/email_verification.py`, `backend/app/routes/auth.py`, `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md`.
Why: Audit consumers can misclassify unmounted handlers as active API truth even though runtime auth behavior is already mounted elsewhere.
Risk: Incorrect route accounting, misleading remediation plans, and duplicate auth logic being treated as current.
Fix: Keep mounted auth truth in `backend/app/routes/api_auth.py` and `backend/app/routes/email_verification.py`, and document the mounted inventory: `POST /auth/login`, `POST /auth/request-password-reset`, compatibility alias `POST /auth/forgot-password`, `POST /auth/reset-password`, `POST /auth/send-verification`, `GET /auth/verify-email`, `POST /auth/refresh`, and `GET /auth/me`. Treat `backend/app/routes/auth.py` as legacy-only because it is not mounted by `backend/app/main.py`.
Test: Verify `backend/app/main.py` includes `api_auth.router` and `email_verification.router` and does not include `auth.router`, then verify audit docs no longer describe `backend/app/routes/auth.py` as active truth or omit verification-email ownership.

### P0-3: Fix media presign mismatch
What: Flutter/landing request `/media/presign`, but backend exposes `/media/sign` and studio-specific presign endpoints.
Where: `frontend/lib/services/media_service.dart`, `frontend/landing/lib/media.ts`, `backend/app/routes/media.py`, `backend/app/routes/studio.py`.
Why: Media upload/download flows fail or rely on legacy paths.
Risk: Course/lesson media broken.
Fix: Implement `/media/presign` server-side or switch clients to `/media/sign` + `/media/stream/{token}` and `/studio/lessons/{id}/media/presign`.
Test: Add backend integration test for media presign/stream and a Flutter upload test using the same endpoints.

### P0-4: Resolve Flutter analyze failures
What: `flutter analyze` reports 149 issues including missing `package:aveli/*` imports and undefined symbols.
Where: `frontend/lib/features/payments/services/stripe_service.dart`, `frontend/lib/features/seminars/presentation/seminar_booking_page.dart`, `frontend/lib/features/studio/*`, `frontend/lib/services/media_service.dart`.
Why: CI/build will fail when analysis is required.
Risk: Release pipeline blocked.
Fix: Update imports to `package:wisdom/*`, remove dead files, or move legacy modules to `archive/`.
Test: Require `flutter analyze` in CI to stay green.

### P0-5: Close RLS gaps for entitlements/feed
What: `app.course_entitlements` has no RLS; feed policy allows all rows.
Where: `supabase/migrations/*` (see `docs/audit/20260109_aveli_visdom_audit/RLS_MATRIX.md`).
Why: Unauthorized data access is possible.
Risk: Data leakage/compliance risk.
Fix: Enable RLS for `app.course_entitlements` and tighten `activities_read` policy.
Test: Add RLS tests verifying select/update restrictions (backend or SQL tests).

### P1-1: OAuth/Supabase token bridge
What: Supabase OAuth session parsing exists in Flutter but backend only accepts its own JWTs.
Where: `frontend/lib/core/deeplinks/deep_link_service.dart`, `backend/app/auth.py`.
Why: OAuth users will not be authenticated in backend.
Risk: Social login unusable.
Fix: Add token exchange endpoint or remove Supabase OAuth flow.
Test: End-to-end OAuth login test verifying backend accepts the session token.

### P1-2: Observability correlation
What: Request IDs are created but not injected into logs; user_id not set in log context.
Where: `backend/app/logging_utils.py`, `backend/app/logging_context.py`, `backend/app/middleware/request_context.py`.
Why: Hard to trace incidents across requests/webhooks.
Risk: Longer MTTR.
Fix: Attach `RequestContextFilter` to logger and call `set_user_context` in auth dependency.
Test: Add a logging unit test to confirm request_id/user_id fields exist in JSON log output.

### P1-3: Rate limiting for abuse-prone endpoints
What: Rate limiting exists only in unmounted auth router.
Where: `backend/app/routes/api_auth.py`, `backend/app/routes/stripe_webhooks.py`, `backend/app/routes/livekit_webhooks.py`.
Why: Brute force and webhook abuse not mitigated.
Risk: Account compromise, DoS.
Fix: Add rate limiting middleware or per-endpoint throttling to mounted routes.
Test: Add tests for rate limit thresholds and 429 responses.

### P1-4: Quiz route audit drift
What: January audit notes still record `PATCH /studio/quizzes/{id}/questions/{id}`, but current frontend and mounted backend both use `PUT /studio/quizzes/{id}/questions/{id}`.
Where: `frontend/lib/features/studio/data/studio_repository.dart`, `backend/app/routes/studio.py`, `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`.
Why: Audit consumers can treat a historical PATCH claim as current route truth even though the live contract is already aligned.
Risk: Incorrect route accounting and misleading backlog prioritization for teacher studio.
Fix: Keep `PUT /studio/quizzes/{id}/questions/{id}` as the canonical route and preserve the old PATCH claim only as historical context.
Test: Verify frontend uses `_client.put(...)` for quiz question updates and backend exposes `@router.put("/quizzes/{quiz_id}/questions/{question_id}")` with no quiz-question PATCH route.

### P2-1: Typed API contracts
What: Many Flutter repositories use raw `Map<String,dynamic>`.
Where: `frontend/lib/features/payments/data/payments_repository.dart`, `frontend/lib/features/studio/data/studio_repository.dart`.
Why: Contracts drift silently.
Risk: Runtime failures from schema mismatches.
Fix: Generate shared API models from OpenAPI or add JSON schema validation.
Test: Contract tests comparing backend responses to frontend models.

### P2-2: Extend performance monitoring
What: Metrics exist for LiveKit only; no request/DB timings.
Where: `backend/app/metrics.py`, `backend/app/main.py`.
Why: Limited insight into latency hot spots.
Risk: Performance regressions undetected.
Fix: Add request duration metrics and DB query timing logs.
Test: Add smoke test to assert metrics endpoint includes new counters.

## Artifacts (appendices)
- System Map: `docs/audit/20260109_aveli_visdom_audit/SYSTEM_MAP.md`
- API Catalog (human): `docs/audit/20260109_aveli_visdom_audit/API_CATALOG.md`
- API Catalog (JSON): `docs/audit/20260109_aveli_visdom_audit/API_CATALOG.json`
- API Usage Diff: `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`
- Security Review: `docs/audit/20260109_aveli_visdom_audit/SECURITY_REVIEW.md`
- RLS Matrix: `docs/audit/20260109_aveli_visdom_audit/RLS_MATRIX.md`
- E2E Flows: `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md`
- Frontend Review: `docs/audit/20260109_aveli_visdom_audit/FRONTEND_REVIEW.md`
- Ops + Observability: `docs/audit/20260109_aveli_visdom_audit/OPS_OBSERVABILITY.md`
- Quality Report: `docs/audit/20260109_aveli_visdom_audit/QUALITY_REPORT.md`
