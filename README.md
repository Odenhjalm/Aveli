# Aveli Monorepo

Flutter client, FastAPI backend, Supabase schema, and a Next.js landing page in one place. Supabase holds the canonical database schema; all migrations live under `supabase/migrations`.

```
.
├── backend/            # FastAPI app, Stripe/LiveKit, scripts, Dockerfile
├── frontend/           # Flutter app (lib/android/ios/web) + landing (Next.js)
│   └── landing/        # Marketing/landing site (Next.js)
├── supabase/           # SQL migrations (single source of truth)
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
- Copy `.env.example` → `.env` (root), `.env.example.backend` → `.env.backend`, `.env.example.flutter` → `frontend/.env` as needed.
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
Migrations source: `supabase/migrations/*.sql`.

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
flutter run   # uses API_BASE_URL/SUPABASE_* from frontend/.env
```
Android emulator uses `http://10.0.2.2:8080` automatically via the env resolver.

## Landing (Next.js)
```bash
cd frontend/landing
npm install
npm run dev   # http://localhost:3000
```
Environment: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_API_BASE_URL` (default `http://backend:8080` in compose).

## Docker (backend + landing)
```bash
docker compose --env-file .env.docker up --build
# Backend: http://localhost:8080, Landing: http://localhost:3000
```

## Deployment (Fly.io)
- `fly.toml` points to `backend/Dockerfile`, internal port `8080`, HTTP checks on `/healthz` + `/readyz`.
- Set secrets via `flyctl secrets set` using the keys from `docs/ENV_VARS.md`.
- Deploy with `flyctl deploy`.

## Tooling
- Scripts live in `backend/scripts` (and via root symlink `scripts/` for compatibility).
- MCP Supabase helper: `backend/scripts/mcp_supabase.py` (uses `.vscode/mcp.json`).
- Course import/QA utilities: see `docs/BACKEND_STRUCTURE.md` and `docs/DEPLOYMENT.md`.

## Documentation
- Security/rotation: `docs/SECURITY.md`
- Deployment (Fly.io + compose): `docs/DEPLOYMENT.md`
- Backend layout/services: `docs/BACKEND_STRUCTURE.md`
- Env reference: `docs/ENV_VARS.md`
