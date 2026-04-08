# System Map (Phase 0)

## Topology (Repo structure)
- **Backend (FastAPI)**: `backend/` (routes, services, repositories, scripts, Dockerfile). Routers are wired in `backend/app/main.py` and include `/auth`, `/courses`, `/studio`, `/admin`, `/api/billing`, `/webhooks`, etc.
  - Source: `README.md`, `docs/BACKEND_STRUCTURE.md`, `backend/app/main.py`.
- **Flutter app**: `frontend/` (Flutter app for mobile/desktop/web). Uses env from `frontend/.env` and talks to the backend API.
  - Source: `README.md`, `frontend/pubspec.yaml`.
- **Landing (Next.js)**: `frontend/landing/` (marketing site + forms).
  - Source: `README.md`, `frontend/landing/package.json`, `frontend/landing/next.config.js`.
- **Supabase schema + migrations**: `supabase/migrations/` (single source of truth for DB schema and policies).
  - Source: `README.md`, `supabase/migrations/*`.
- **Ops/verification**: `ops/verify_all.sh`, `backend/scripts/*`, root `verify_all.sh`.
  - Source: `verify_all.sh`, `ops/verify_all.sh`.
- **CI**: GitHub Actions workflows in `.github/workflows/`.
  - `backend-ci.yml`, `flutter.yml`, `web-ci.yml`, `release-android.yml`, `import-dry-run.yml`, `codex-agent.yml`.

## Local start commands (Golden paths)
- **Backend**
  - Install deps: `cd backend && poetry install --no-interaction`
  - Run: `PORT=8080 poetry run uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload`
  - Health: `/healthz`, Ready: `/readyz`
  - Source: `README.md`, `starta_backend.md`, `backend/app/main.py`.
- **Flutter**
  - Setup: `cd frontend && flutter pub get`
  - Tests: `flutter test`
  - Run: `flutter run`
  - Source: `README.md`.
- **Landing (Next.js)**
  - Setup: `cd frontend/landing && npm install`
  - Run: `npm run dev` (http://localhost:3000)
  - Source: `README.md`, `frontend/landing/package.json`.
- **Supabase migrations**
  - `SUPABASE_DB_URL=postgres://... backend/scripts/apply_supabase_migrations.sh`
  - Source: `README.md`, `backend/scripts/apply_supabase_migrations.sh`.
- **Docker (backend + landing)**
  - `docker compose --env-file .env.docker up --build`
  - Source: `README.md`, `docker-compose.yml`.

## Golden path verification (verify_all)
**Command run:**
```
APP_ENV=development BACKEND_ENV_FILE=/tmp/aveli_env_dummy BACKEND_ENV_OVERLAY_FILE= ./verify_all.sh
```
**Reason for override:** `ops/env_load.sh` sources `backend/.env` by default. Per non-negotiable rules, I did not read or modify secrets; the env file override points to an empty temp file to avoid loading secrets (see `ops/env_load.sh`).

**Result:** `verify_all` failed at **Env validation** due to missing required keys (expected with empty env file). Output shows missing Stripe, Supabase, JWT, and frontend envs.
- Output excerpt: command output from `./verify_all.sh` (see execution log above) shows missing `SUPABASE_URL`, `SUPABASE_*_KEY`, `JWT_*`, `STRIPE_*`, `API_BASE_URL`, `OAUTH_REDIRECT_*`, `NEXT_PUBLIC_*` etc.
- Because `env_validate` is a blocking step, the pipeline stopped before poetry install/tests/smoke/Flutter/landing steps.
- Source: `ops/verify_all.sh`, `ops/env_validate.sh`.

## Notes
- Default env loading reads `backend/.env` and optional overlays (`ops/env_load.sh`).
- Environment keys and usage documented in `docs/ENV_VARS.md`.
