# Lokal backend + canonical native DB

Mal: kora FastAPI-backenden lokalt mot native PostgreSQL utan Docker som canonical replay-krav.

Viktig avgransning:
- For lokal MCP-audit, test och verifiering ar den auktoritativa lokala DB-kallan `backend/supabase/baseline_slots`.
- Canonical lokal replay-target ar `postgresql://postgres:postgres@127.0.0.1:5432/aveli_local`.
- `supabase/migrations/*.sql` ar production migration source only och far inte ersatta baseline authority lokalt.

## 1) Forbered lokal env

```bash
cp backend/.env.local.example backend/.env.local
cp backend/.env.production.example backend/.env.production   # valfritt, endast referens
chmod 400 backend/.env.production
```

Viktigt:
- `backend/.env.production` ar read-only referens och ska inte anvandas som lokal baseline-kalla.
- `backend/.env.local` ska peka pa `127.0.0.1:5432/aveli_local`.

## 2) Sakra native lokal databas

```bash
backend/scripts/ensure_db.sh
```

Detta verifierar att native PostgreSQL svarar pa `127.0.0.1:5432` och skapar `aveli_local` om den saknas.

## 3) Materialisera canonical local baseline

```bash
backend/scripts/replay_baseline.sh
```

Detta applicerar auth-substrate, baseline slots och storage-substrate mot `127.0.0.1:5432/aveli_local`.

## 4) Starta backend lokalt

```bash
backend/scripts/start_backend.sh
```

Halsokontroller:

```bash
curl -f http://127.0.0.1:8080/healthz
curl -f http://127.0.0.1:8080/readyz
```

Verifiera att uppstarten skriver `DB target: 127.0.0.1:5432/aveli_local`.

## 5) Cloud-klon ar referensworkflow, inte authority

Om du behover klona cloud-data lokalt som referensinput ska `LOCAL_DB_URL` sattas explicit till den native targeten:

```bash
export LOCAL_DB_URL='postgresql://postgres:postgres@127.0.0.1:5432/aveli_local'
export SUPABASE_DB_URL='postgresql://...sslmode=require'
backend/scripts/clone_cloud_db_to_local.sh clone
```

Cloud-kloner far inte omdefiniera canonical local verification truth.

## 6) Legacy Docker-path

`backend/scripts/local_db.sh` och `docker-compose.yml` ar legacy/reference-only for lokal DB tills native replay-pathen ar verifierad end-to-end.
