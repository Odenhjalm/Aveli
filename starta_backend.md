# Starta backend lokalt

Backenden ligger i `backend/`.

For canonical lokal replay och verifiering ar DB-target:

`127.0.0.1:5432/aveli_local`

## Snabbstart

```bash
cp backend/.env.local.example backend/.env.local
backend/scripts/ensure_db.sh
backend/scripts/replay_baseline.sh
backend/scripts/start_backend.sh
```

Halsokontroller:

```bash
curl -f http://127.0.0.1:8080/healthz
curl -f http://127.0.0.1:8080/readyz
curl -f http://127.0.0.1:8080/landing/services
```

`backend/scripts/local_db.sh` ar ett legacy Docker-hjalpmedel och ar inte langre den canonical replay-vagen.
