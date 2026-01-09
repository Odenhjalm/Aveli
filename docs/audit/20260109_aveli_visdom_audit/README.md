# Aveli/Visdom Audit - 20260109

## Executive Summary
- Current state: Backend + DB schema are extensive and the core product flows (auth, courses, seminars, billing) exist in code, but there are frontend/backend contract mismatches and auth/observability gaps that will surface as runtime failures.
- Stable areas:
  - Flutter unit/widget tests pass (`flutter test`).
  - Landing site tests and lint pass (`npm test`, `npm run lint`).
  - Core API surface is implemented (177 endpoints in `docs/audit/20260109_aveli_visdom_audit/API_CATALOG.md`).
- Highest risk areas:
  - Payment and media flows: frontend calls endpoints that do not exist in the mounted backend (`/payments/*`, `/checkout/session`, `/media/presign`).
  - Password reset endpoints exist but are unmounted; UI currently points to those endpoints.
  - RLS: `app.course_entitlements` is missing RLS and feed policy is permissive.
  - Flutter static analysis fails due to missing `package:aveli/*` imports, which would fail CI/build.

Launch blockers (must fix before launch): endpoint mismatches, unmounted routes, RLS gaps, and broken Flutter analysis. Post-launch improvements: observability correlation, rate limiting, and expanded testing.

## Prioritized Action Plan

### P0-1: Align payment endpoints (frontend vs backend)
What: Frontend uses `/payments/*` and `/checkout/session` while backend exposes `/api/checkout/*`, `/api/billing/*`, and `/orders`.
Where: `frontend/lib/features/payments/data/payments_repository.dart`, `frontend/lib/data/repositories/orders_repository.dart`, `frontend/lib/features/payments/services/stripe_service.dart`, `backend/app/routes/billing.py`, `backend/app/routes/api_checkout.py`, `backend/app/routes/api_orders.py`, `backend/app/main.py`.
Why: Core purchase and subscription flows will return 404/405 today.
Risk: Payments and memberships fail; revenue impact.
Fix: Either (a) update Flutter to call `/api/checkout/create`, `/api/billing/create-subscription`, `/api/billing/customer-portal`, `/orders`, or (b) mount and fully implement the `/payments` router.
Test: Add integration tests for course checkout + membership (backend) and a Flutter contract test asserting endpoint availability (see `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`).

### P0-2: Mount or replace password reset endpoints
What: `/auth/forgot-password` and `/auth/reset-password` are called by Flutter but live only in unmounted router.
Where: `frontend/lib/api/auth_repository.dart`, `backend/app/routes/auth.py`, `backend/app/main.py`.
Why: Password reset flow is broken in production.
Risk: Users cannot recover accounts.
Fix: Mount `backend/app/routes/auth.py` or migrate Flutter to a mounted endpoint.
Test: Add backend tests for forgot/reset and a Flutter widget test for success/error handling.

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

### P1-4: Quiz update method mismatch
What: Flutter uses `PATCH /studio/quizzes/{id}/questions/{id}` but backend expects `PUT`.
Where: `frontend/lib/features/studio/data/studio_repository.dart`, `backend/app/routes/studio.py`.
Why: Quiz question updates fail.
Risk: Teacher studio breakage.
Fix: Align method in Flutter or add PATCH handler in backend.
Test: Add integration test for quiz question update.

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
