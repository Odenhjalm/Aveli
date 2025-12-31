# Launch Readiness Report

Status: NOT READY (backend/.env missing + test/build blockers)

## Pass/Fail Matrix
| Area | Status | Notes |
| --- | --- | --- |
| Env guard (backend/.env not tracked) | PASS | guardrails active |
| Env validation | FAIL | backend/.env missing |
| Env contract check | FAIL | backend/.env missing |
| Stripe test verification | FAIL | backend/.env missing |
| Supabase env verification | FAIL | backend/.env missing |
| Remote DB read-only verify | SKIP | SUPABASE_DB_URL/DATABASE_URL not set |
| RLS enabled for app tables | SKIP | remote DB verify not run |
| RLS policies present | SKIP | remote DB verify not run |
| Storage buckets + policies | SKIP | remote DB verify not run |
| Backend tests | FAIL | backend/.env missing (config raises) |
| Backend smoke (Stripe checkout + membership) | FAIL | backend could not start |
| Flutter tests | FAIL | unit tests pass; integration tests fail on linux device |
| Landing tests | PASS | vitest ok |
| Landing build | FAIL | missing `@sentry/nextjs` |

## Fixes Applied
- Backend config now loads only `backend/.env` and fails fast if missing; repo guardrails block committing env files.
- Added `ENV_REQUIRED_KEYS.txt` + `backend/scripts/env_contract_check.py` and wired into `ops/verify_all.sh`.
- Added `backend/scripts/stripe_verify_test_mode.py` and `backend/scripts/supabase_verify_env.py`.
- Updated backend env templates/docs to use `backend/.env` only and include QA/import keys.
- `ops/verify_all.sh` installs deps (Poetry/NPM) and auto-selects Flutter devices; remote DB verify loads `backend/.env` and uses the allowlist.

## Remaining Blockers
- `backend/.env` missing in the clean worktree (blocks env checks, Stripe/Supabase verify, backend tests/smoke).
- Remote DB verify still needs `SUPABASE_DB_URL`/`DATABASE_URL` to run read-only checks.
- Flutter integration tests fail on `FLUTTER_DEVICE=linux` (app fails to start / no debug connection).
- Landing build blocked by missing `@sentry/nextjs`.

## Verification Runs
- Local verify_all (FLUTTER_DEVICE=linux): FAILED (env missing; backend tests/smoke failed; Flutter integration failed; landing build failed)
- Remote DB verify: SKIPPED (SUPABASE_DB_URL/DATABASE_URL not set)

## Next 5 Actions
1. Create `backend/.env` from `backend/.env.example` (test keys only) and re-run `ops/env_validate.sh`.
2. Re-run `backend/scripts/env_contract_check.py`, `stripe_verify_test_mode.py`, and `supabase_verify_env.py`.
3. Export `SUPABASE_DB_URL` (read-only) and rerun `ops/db_verify_remote_readonly.sh`.
4. Fix Flutter integration test environment for linux (device availability + required runtime env).
5. Add `@sentry/nextjs` to `frontend/landing/package.json` or gate Sentry init for builds.

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

## Remote DB Verify (read-only)
Status: SKIPPED
Reason: SUPABASE_PROJECT_REF not set and SUPABASE_URL not provided

## Remote DB Verify (read-only)
Status: SKIPPED
Reason: SUPABASE_PROJECT_REF not set and SUPABASE_URL not provided

## Remote DB Verify (read-only)
Status: SKIPPED
Reason: SUPABASE_PROJECT_REF not set and SUPABASE_URL not provided

## Verification Run (ops/verify_all.sh)
- Env guard (backend/.env not tracked): PASS
- Env validation: FAIL
- Env contract check: FAIL
- Stripe test verification: FAIL
- Supabase env verification: FAIL
- Remote DB verify: SKIP
- Local DB reset: SKIP
- Backend tests: FAIL
- Backend smoke: FAIL
- Flutter tests: FAIL
- Landing tests: PASS
- Landing build: FAIL
