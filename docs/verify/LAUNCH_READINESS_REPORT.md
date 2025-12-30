# Launch Readiness Report

Status: NOT READY (env gaps + build/test blockers)

## Pass/Fail Matrix
| Area | Status | Notes |
| --- | --- | --- |
| Env validation (backend + Flutter + landing) | FAIL | required env vars missing in this run |
| Local DB reset + migrations | SKIP | not requested |
| Remote DB read-only verify | SKIP | SUPABASE_DB_URL/DATABASE_URL not set |
| RLS enabled for app tables | SKIP | remote DB verify not run |
| RLS policies present | SKIP | remote DB verify not run |
| Storage buckets + policies | SKIP | remote DB verify not run |
| Backend tests | FAIL | Settings validation failed (Supabase env missing) |
| Backend smoke (Stripe checkout + membership) | FAIL | backend could not start without Supabase env |
| Stripe webhook verification | FAIL | backend smoke failed |
| Flutter tests | FAIL | unit tests pass; integration tests cannot run on web device |
| Landing build/tests | FAIL | tests pass; build fails (missing `@sentry/nextjs`) |

## Fixes Applied
- Flutter env resolver now accepts `SUPABASE_ANON_KEY` as a fallback for `SUPABASE_PUBLISHABLE_API_KEY`.
- QA teacher smoke supports strict CI mode and deterministic Stripe webhook signing.
- Added ops scripts for env validation, DB verify/reset, and one-command verification.
- `ops/verify_all.sh` now installs backend/landing deps and auto-selects a Flutter device.
- Remote DB verify derives `SUPABASE_PROJECT_REF` from `SUPABASE_URL` when available.

## Remaining Blockers
- Required env vars not set in this environment (Supabase, Stripe, OAuth).
- Remote DB verify needs `SUPABASE_DB_URL` (read-only).
- Backend tests/smoke blocked by missing Supabase env settings.
- Flutter integration tests need a non-web device (e.g., `FLUTTER_DEVICE=linux`).
- Landing build blocked by missing `@sentry/nextjs` dependency.

## Verification Runs
- Local verify_all: FAILED (env missing; backend tests/smoke failed; Flutter integration failed; landing build failed)
- Remote DB verify: SKIPPED (SUPABASE_DB_URL/DATABASE_URL not set)

## Next 5 Actions
1. Export required env vars (see `docs/verify/ENV_CONTRACT.md`) and re-run `ops/env_validate.sh`.
2. Provide `SUPABASE_DB_URL` (read-only) and rerun `ops/db_verify_remote_readonly.sh`.
3. Re-run `ops/verify_all.sh` with `FLUTTER_DEVICE=linux` (or a connected device).
4. Add `@sentry/nextjs` to `frontend/landing/package.json` or gate Sentry config to unblock build.
5. Re-run `ops/verify_all.sh` and update this report with PASS/FAIL results.

## Remote DB Verify (read-only)
Status: SKIPPED
Reason: SUPABASE_DB_URL/DATABASE_URL not set

## Verification Run (ops/verify_all.sh)
- Env validation: PASS (warnings only)
- Remote DB verify: SKIP
- Local DB reset: SKIP
- Backend tests: FAIL
- Backend smoke: FAIL
- Flutter tests: FAIL
- Landing tests: PASS
- Landing build: FAIL
