# Aveli Monorepo

Flutter client, FastAPI backend, Supabase schema, and a Next.js landing page in one place. Production migrations live under `supabase/migrations`. For local MCP audit, testing, and verification, the authoritative local DB baseline is `backend/supabase/baseline_slots`, materialized with `backend/scripts/replay_baseline.sh` on local Postgres.

```
.
├── backend/            # FastAPI app, Stripe/LiveKit, scripts, Dockerfile
├── frontend/           # Flutter app (lib/android/ios/web) + landing (Next.js)
│   └── landing/        # Marketing/landing site (Next.js)
├── supabase/           # Production SQL migrations
├── docs/               # Architecture, security, deployment, env docs
├── .env.example*       # Safe templates for backend + Flutter
├── docker-compose.yml  # Backend + landing for local dev
└── fly.toml            # Fly.io deployment config (backend)
```

## Prerequisites
- Python 3.11+, Poetry
- Flutter 3.24+ (run inside `frontend/`)
- Node 18+ for the Next.js landing (`frontend/landing`)
- `psql` client
- Docker (optional for compose)
- Supabase project (URL, anon key, service role, DB URL), Stripe keys, LiveKit keys

## Environment
- Copy `.env.example` → `.env` (root), `.env.example.backend` → `.env.backend`.
- Flutter: copy `.env.example.flutter` → `frontend/.env.local` for local defines (or provide `--dart-define` flags directly). Use a separate `frontend/.env.web` for local web runs only, and run `frontend/scripts/guard_web_defines.sh` to block secrets. Production web deploys must use Netlify env vars plus `netlify.toml`, not a checked-in `.env` file.
- Do **not** commit real keys (.env files are ignored).
- Backend listens on port `8080` by default; update `API_BASE_URL`/`NEXT_PUBLIC_API_BASE_URL` accordingly.

## Backend (FastAPI)
```bash
cd backend
poetry install --no-interaction
PORT=8080 poetry run uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
```
- Health: `/healthz`, Ready: `/readyz`.
- Supabase Storage/Stripe/LiveKit features require the corresponding env vars.

### Supabase migrations
```bash
SUPABASE_DB_URL=postgres://... \
SUPABASE_DB_PASSWORD=... \
backend/scripts/apply_supabase_migrations.sh
```
Production migration source: `supabase/migrations/*.sql` only.

### Local DB authority for MCP and verification
- Authoritative local DB source: `backend/supabase/baseline_slots`.
- Materialize that source on local Postgres with `backend/scripts/replay_baseline.sh`.
- `supabase/migrations/*.sql` remains the production migration source only.
- Cloud clones and legacy DB state are reference inputs only and must not redefine local verification truth.

### Backend tests & lint
```bash
make backend.test     # pytest
make backend.lint     # ruff
make qa.teacher       # smoke against a running backend (port 8080)
```

## Flutter app
```bash
cd frontend
flutter pub get
flutter test
flutter run --dart-define-from-file=.env.local
```
Android emulator uses `http://10.0.2.2:8080` automatically via the env resolver.
For web builds, use a web-specific defines file:
```bash
flutter run -d chrome --dart-define-from-file=.env.web
```
Ensure `.env.local`/`.env.web` include `API_BASE_URL`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_API_KEY`, and `OAUTH_REDIRECT_WEB`/`OAUTH_REDIRECT_MOBILE` as needed.

## Landing (Next.js)
```bash
cd frontend/landing
npm install
npm run dev   # http://localhost:3000
```
Environment: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` (set to the Supabase publishable key), `NEXT_PUBLIC_API_BASE_URL` (default `http://backend:8080` in compose).

## Docker (backend + landing)
```bash
docker compose --env-file .env.docker up --build
# Backend: http://localhost:8080, Landing: http://localhost:3000
```

## Deployment
- Canonical production release is manual and exact-SHA based; see `docs/DEPLOYMENT.md`.
- Database: apply migrations from root `supabase/migrations/*.sql` only. Do not use `backend/supabase/` or `cd backend && supabase db push` for production.
- Backend: deploy Fly from a clean worktree at the exact commit on `main` using `fly.toml` and `backend/Dockerfile`.
- Frontend: deploy the same commit via Netlify source build using `netlify.toml`. Do not upload a local `frontend/build/web` artifact to production.
- Post-deploy: verify `/healthz`, `/readyz`, and one authenticated runtime-media playback path.

## Tooling
- Scripts live in `backend/scripts` (and via root symlink `scripts/` for compatibility).
- MCP Supabase helper: `backend/scripts/mcp_supabase.py` (uses `.vscode/mcp.json`).
- Course import/QA utilities: see `docs/BACKEND_STRUCTURE.md` and `docs/DEPLOYMENT.md`.

## Task Branch Guardrail
Install once per clone:
```bash
make guardrails.install
```
Start every new task on a fresh branch:
```bash
make task.branch TASK="short task name"
```
The repo hooks block commit/push on protected branches (`main`, `master`, `develop`, `dev`, `production`, `release`).

## Documentation
- Security/rotation: `docs/SECURITY.md`
- Deployment (Fly.io + compose): `docs/DEPLOYMENT.md`
- Backend layout/services: `docs/BACKEND_STRUCTURE.md`
- Env reference: `docs/ENV_VARS.md`
- Media behavior is governed by Media Contract v1: `docs/MEDIA_CONTRACT_v1.md`
