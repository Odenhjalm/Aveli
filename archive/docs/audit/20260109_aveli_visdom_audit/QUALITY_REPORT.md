# Quality Report (Phase 6)

## Test inventory
- Backend tests: `backend/tests/` and `backend/context7/tests/` (auth, courses, seminars, livekit, webhooks, RLS, admin, storage, studio permissions). Example files: `backend/tests/test_courses_enroll.py`, `backend/tests/test_livekit_tokens.py`, `backend/tests/test_supabase_postgrest_rls.py`, `backend/context7/tests/test_plan_execute_v1.py`.
- Flutter tests: `frontend/test/` (unit + widget), `frontend/integration_test/` (integration).
- Landing (Next.js) tests: `frontend/landing/tests/` (Vitest).

## Commands executed and results
- Flutter unit/widget tests:
  - Command: `flutter test`
  - Result: PASS (all tests passed)
- Flutter static analysis:
  - Command: `flutter analyze`
  - Result: FAIL (149 issues; missing `package:aveli/*` imports, undefined symbols, unused imports, and lint warnings).
  - Example failing files: `frontend/lib/features/payments/services/stripe_service.dart`, `frontend/lib/features/seminars/presentation/seminar_booking_page.dart`, `frontend/lib/services/media_service.dart`.
- Landing tests:
  - Command: `npm test`
  - Result: PASS (2 test files, 3 tests).
- Landing lint:
  - Command: `npm run lint`
  - Result: PASS (no ESLint warnings).

## Skipped / blocked
- Backend tests (`pytest`) were not executed because importing `backend/app/config.py` loads `.env` via `SettingsConfigDict(env_file=('.env','../.env'))` and would read `backend/.env` (forbidden by non-negotiable rules).
- Backend lint (`ruff`) not executed: `ruff` is not installed globally and running `poetry run ruff` would require installing dependencies; also backend tests would still read `.env`.
- Flutter integration tests in `frontend/integration_test/` were not executed (require device/emulator; not part of `flutter test`).

## Gaps / missing coverage (suggested backlog)
P0 (launch blockers):
- Auth: add backend tests for `/auth/forgot-password` and `/auth/reset-password` once the router is mounted.
- Payments: add integration tests for Stripe webhook signature failures and for `/api/billing/session-status` polling behavior.
- RLS: add explicit tests for tables with missing or permissive policies (see `docs/audit/20260109_aveli_visdom_audit/RLS_MATRIX.md`).

P1:
- End-to-end tests for course checkout -> entitlement -> lesson access (backend + Flutter).
- Webhook processing reliability tests for LiveKit retries and idempotency.
- Frontend API contract tests to catch `/payments/*` vs `/api/*` mismatches (see `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`).

P2:
- UI snapshot tests for key Flutter screens (login, course list, seminar join).
- Load tests for media streaming (`/media/stream/{token}`) and lesson downloads.
