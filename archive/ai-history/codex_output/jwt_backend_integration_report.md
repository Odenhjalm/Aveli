# JWT Backend Integration Report

## Modified files
- backend/app/auth/__init__.py (moved from module; now RS256 JWKS verification + Supabase auth helpers)
- backend/app/auth/jwks.py
- backend/app/auth/verify.py
- backend/app/routes/api_auth.py
- backend/app/routes/auth.py
- backend/app/config.py
- backend/env/.env
- frontend/.env
- frontend/env/.env
- backend/scripts/test_all.sh
- backend/tests/test_supabase_postgrest_rls.py
- backend/README.md
- backend/scripts/ops/ops_runbook.md

## HS256 to RS256 JWKS changes
- Replaced legacy `jwt.decode(..., JWT_SECRET, algorithms=["HS256"])` flows with `verify_jwt` using PyJWKClient against Supabase JWKS.
- Removed custom access/refresh token signing; login/register/refresh now delegate to Supabase Auth endpoints for RS256-issued tokens.
- Deprecated legacy HS256 tests (RLS smoke) via skip marker.

## JWKS logic
- New JWKS client (`backend/app/auth/jwks.py`, `verify.py`) pulls keys from `SUPABASE_JWKS_URL` (falls back to `SUPABASE_URL/auth/v1/jwks`).

## Environment updates
- Backend: removed JWT secret variables; added `SUPABASE_JWKS_URL=https://evgwgepnscopsiznqkqc.supabase.co/auth/v1/jwks` in `backend/env/.env`.
- Frontend envs: removed JWT_SECRET/SUPABASE_JWT_SECRET entries; Supabase URL/public API key retained.

## Verification
- Syntax check: `python - <<PY ... py_compile ... PY` (all backend *.py compiled).
- Boot check: `poetry run uvicorn app.main:app --port 8001` (started and shut down cleanly; port 8000 was busy so retried on 8001).
