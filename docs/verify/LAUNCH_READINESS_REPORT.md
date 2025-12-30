# Launch Readiness Report

Status: NOT READY (env + dependency gaps)

## Pass/Fail Matrix
| Area | Status | Notes |
| --- | --- | --- |
| Env validation (backend + Flutter + landing) | FAIL | required env vars missing in this run |
| Local DB reset + migrations | SKIP | not requested |
| Remote DB read-only verify | SKIP | SUPABASE_PROJECT_REF not set/allowlisted |
| RLS enabled for app tables | SKIP | remote DB verify not run |
| RLS policies present | SKIP | remote DB verify not run |
| Storage buckets + policies | SKIP | remote DB verify not run |
| Backend tests | FAIL | backend deps/env missing (poetry install + env required) |
| Backend smoke (Stripe checkout + membership) | FAIL | backend deps/env missing |
| Stripe webhook verification | FAIL | backend smoke failed |
| Flutter tests | FAIL | unit tests passed; integration tests need device flag |
| Landing build/tests | FAIL | npm deps not installed (vitest/next missing) |

## Fixes Applied
- Flutter env resolver now accepts `SUPABASE_ANON_KEY` as a fallback for `SUPABASE_PUBLISHABLE_API_KEY`.
- QA teacher smoke supports strict CI mode and deterministic Stripe webhook signing.
- Added ops scripts for env validation, DB verify/reset, and one-command verification.

## Remaining Blockers
- Required env vars not set in the verification environment (Supabase, Stripe, OAuth).
- Backend Python dependencies not installed (poetry install required).
- Landing dependencies not installed (npm ci required).
- Flutter integration tests need a specific device flag (chrome/linux).
- Remote DB verification blocked by missing allowlist/project ref.

## Verification Runs
- Local verify_all: FAILED (missing env/deps)
- Remote DB verify: SKIPPED (no allowlist/project ref)

## Next 5 Actions
1. Export required env vars (see docs/verify/ENV_CONTRACT.md) and re-run ops/env_validate.sh.
2. Add SUPABASE_PROJECT_REF to docs/ops/SUPABASE_ALLOWLIST.txt, then run ops/db_verify_remote_readonly.sh.
3. Run poetry install in backend and re-run ops/verify_all.sh.
4. Run npm ci in frontend/landing and re-run ops/verify_all.sh.
5. Re-run Flutter integration tests with FLUTTER_DEVICE=chrome (or linux) and update this report.

## Remote DB Verify (read-only)
Status: SKIPPED
Reason: SUPABASE_PROJECT_REF not set

## Verification Run (ops/verify_all.sh)
- Env validation: PASS
- Remote DB verify: SKIP
- Local DB reset: SKIP
- Backend tests: FAIL
- Backend smoke: FAIL
- Flutter tests: FAIL
- Landing tests: FAIL
- Landing build: FAIL
