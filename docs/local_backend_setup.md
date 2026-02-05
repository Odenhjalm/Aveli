# Lokal backend + lokal DB-klon (NO DEPLOY)

Mål: köra FastAPI-backenden lokalt mot en **lokal Postgres** som är en **klon av cloud (Supabase/Postgres)** – utan deploy, utan schemaändringar i cloud och utan migrations mot prod.

## 1) Starta backend lokalt (med `.env.local`)

Skapa/uppdatera env-filer:

```bash
cp backend/.env.local.example backend/.env.local
cp backend/.env.production.example backend/.env.production   # valfritt (för referens)
chmod 400 backend/.env.production
```

Viktigt:
- `backend/.env.production` är **read-only** och ska **inte** användas lokalt.
- `backend/.env.local` måste peka på **lokal DB** via `DATABASE_URL=postgresql://...@127.0.0.1:.../...`.

Starta FastAPI:

```bash
backend/scripts/start_backend.sh
```

Hälsokontroller:

```bash
curl -f http://127.0.0.1:8080/healthz
curl -f http://127.0.0.1:8080/readyz
```

## 2) Skapa lokal databas (Docker Postgres)

Starta lokal Postgres-container:

```bash
backend/scripts/local_db.sh up
```

Standard:
- Port: `54322`
- DB: `aveli_local`
- User/pass: `postgres` / `postgres`

Skriv ut connection string:

```bash
backend/scripts/local_db.sh url
```

## 3) Klona cloud-databasen till lokal

### Alternativ A (rekommenderat): Script (dump + restore + verifiering)

```bash
export SUPABASE_DB_URL='postgresql://...sslmode=require'
backend/scripts/clone_cloud_db_to_local.sh clone
```

Dumpen hamnar som default i `out/db_dumps/` (ignoreras av git).

### Alternativ B: Exakta kommandon (manuellt)

1) Starta lokal DB:

```bash
backend/scripts/local_db.sh up
export LOCAL_DB_URL="$(backend/scripts/local_db.sh url)"
```

2) Dump från cloud (schema + data):

```bash
export SUPABASE_DB_URL='postgresql://...sslmode=require'
mkdir -p out/db_dumps
pg_dump -F c --no-owner --no-privileges --dbname "$SUPABASE_DB_URL" -f out/db_dumps/supabase.dump
```

3) Restore till lokal Postgres:

```bash
pg_restore --no-owner --no-privileges --clean --if-exists --dbname "$LOCAL_DB_URL" out/db_dumps/supabase.dump
```

4) Verifiera (tabeller + rader + enums + constraints):

```bash
export REMOTE_DB_URL="$SUPABASE_DB_URL"
export LOCAL_DB_URL
backend/scripts/clone_cloud_db_to_local.sh verify
```

## 4) Miljö-isolering (skydd)

Skydd som finns:
- `backend/scripts/start_backend.sh` vägrar starta om `APP_ENV` är `production/prod/live` (override: `AVELI_ALLOW_PROD_ENV_LOCAL=1`).
- Backend vägrar koppla upp mot Supabase-host utanför cloud-runtime (t.ex. lokalt). Override: `AVELI_ALLOW_REMOTE_DB=1`.

## How to verify backend is using local DB

Start `backend/scripts/start_backend.sh` and confirm it prints `DB target: 127.0.0.1:.../aveli_local`.
Insert a test row via `psql "$(backend/scripts/local_db.sh url)" ...`.
Fetch it via an API endpoint and confirm the value matches.
