# Aveli – Supabase-first stack

This repo contains the entire Aveli platform: Flutter client, FastAPI backend, Next.js landing, and the canonical Supabase schema. Postgres lives in Supabase only; all schema/RLS is defined under `supabase/migrations`.

```
.
├── lib/                     # Flutter app
├── backend/                 # FastAPI + Stripe + LiveKit
├── supabase/migrations/     # Single source of truth for DB + RLS
├── web/                     # Next.js landing (used by docker-compose)
├── scripts/                 # QA + ops helpers
└── docs/                    # Setup + release docs
```

## Requirements
- Python 3.11, Poetry
- Flutter 3.24+, Node 18+
- `psql` client
- Docker (optional, for compose)
- Supabase project (URL, anon key, service role, DB URL)
- Stripe + LiveKit keys for payments/rooms

## Secrets
- Copy `.env.example` → `.env` (and `.env.docker.example` if you use compose).
- Populate Supabase/Stripe/LiveKit/JWT/Media secrets. Do **not** commit real keys; they are ignored via `.gitignore`.

## Supabase schema
Single source: `supabase/migrations/*.sql`.
```
SUPABASE_DB_URL=postgresql://... SUPABASE_DB_PASSWORD=... scripts/apply_supabase_migrations.sh
```
Use MCP (`.vscode/mcp.json`) for live SQL changes; then commit a migration.

## Run backend (local)
```
cd backend
poetry install --no-root
poetry run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```
- `/healthz` basic; `/readyz` checks DB.
- Media/signing uses Supabase Storage when service role key is set.

## Docker (backend + web)
```
docker compose --env-file .env.docker up --build
```
Exposes backend on `8000`, web on `3000`. Requires Supabase+Stripe env vars in `.env.docker`.

## Tests & QA
- Backend: `make backend.test` (pytest). `/readyz` failure path covered.
- Lint: `make backend.lint`
- Supabase migrations: `make supabase.migrate`
- QA: `make qa.teacher` (auth → order → Stripe session → membership)
- Flutter: `flutter test`

## CI (GitHub Actions)
- Applies Supabase migrations to the test DB.
- Installs backend deps, runs pytest.
- Starts backend, runs QA smoke.
- Runs `flutter test`.

## MCP (Supabase operations)
Set `SUPABASE_PAT`, `SUPABASE_DB_URL`, `SUPABASE_SERVICE_ROLE_KEY` in your shell. Use `scripts/mcp_supabase.py` for manual calls (list tables, execute SQL) or let your editor connect via `.vscode/mcp.json`.

## Key commands
```
make backend.dev
make backend.test
make backend.lint
make supabase.migrate
make qa.teacher
docker compose --env-file .env.docker up --build
```

Release checklist lives in `Inför lansering.md` and reflects the Supabase-first architecture. See `docs/local_backend_setup.md` for OS-specific steps.
