# Starta backend lokalt (FastAPI)

Backenden ligger i `backend/`.

För en **helt isolerad lokal miljö** (lokal Postgres-klon av cloud) – följ:
- `docs/local_backend_setup.md`

## Snabbstart (lokalt)

```bash
cp backend/.env.local.example backend/.env.local
backend/scripts/local_db.sh up
backend/scripts/start_backend.sh
```

Hälsokontroller:

```bash
curl -f http://127.0.0.1:8080/healthz
curl -f http://127.0.0.1:8080/readyz
```

Verifiera DB-backed endpoint (utan auth):

```bash
curl -f http://127.0.0.1:8080/landing/services
```
