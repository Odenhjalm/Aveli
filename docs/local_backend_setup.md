# Lokal setup (Supabase + FastAPI + Flutter)

Supabase is the only database. No local Postgres containers. Follow these steps on Ubuntu/macOS/WSL; Docker usage is optional.

## 1) Install tools
- Python 3.11 + `pip install poetry==1.8.3`
- Flutter 3.24+
- Node 18+
- `psql` client
- Docker (optional, for compose)

## 2) Miljöfiler
```
cp .env.example .env
cp .env.docker.example .env.docker   # for compose
```
Fyll `.env` med Supabase URL/keys, Stripe, LiveKit, JWT/Media secrets. Nycklar ska **inte** committas.

## 3) Applicera Supabase-migreringar
```
SUPABASE_DB_URL=postgresql://... \
SUPABASE_DB_PASSWORD=... \
scripts/apply_supabase_migrations.sh
```
Kör detta efter varje schemaändring. Samma script används i CI.

## 4) Starta backend (lokalt)
```
cd backend
poetry install --no-root
poetry run uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
```
- `/healthz` → livstecken
- `/readyz` → DB-anslutningstest

## 5) Docker Compose (backend + web)
```
docker compose --env-file .env.docker up --build
```
- Backend: http://127.0.0.1:8080
- Web: http://127.0.0.1:3000

## 6) Flutter
```
cd frontend
flutter pub get
flutter run -d chrome --dart-define-from-file=.env.web
```
För desktop/emulator: använd `--dart-define-from-file=.env.local` (t.ex. `API_BASE_URL=http://127.0.0.1:8080`).

## 7) QA / tester
- `make backend.test`
- `make backend.lint`
- `make qa.teacher` (kräver giltiga Supabase/Stripe-keys)
- `flutter test`

## 8) MCP
`.vscode/mcp.json` pekar på Supabase MCP. Exportera `SUPABASE_PAT`, `SUPABASE_DB_URL`, `SUPABASE_SECRET_API_KEY` (legacy: `SUPABASE_SERVICE_ROLE_KEY`) innan du kör verktygen eller låter editorn koppla upp.

Troubleshooting:
- 503 på `/readyz`: kontrollera `DATABASE_URL` och att Supabase IP allowlist släpper igenom dig.
- Stripe 401/403: dubbelkolla `STRIPE_SECRET_KEY` och webhook-secrets.
- Upload 413: höj `LESSON_MEDIA_MAX_BYTES` i `.env`.
