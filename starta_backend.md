# Starta backend (FastAPI + Supabase)

Backenden ligger i `backend/` och pratar direkt med Supabase Postgres. Vi kör **inte** längre `make db.*` eller någon lokal Postgres-container.

## Snabbkommandon

```bash
cd /home/oden/Wisdom/backend
poetry install
poetry run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Detaljerade steg finns nedan.

## 1. Förutsättningar

```bash
python3 --version   # ska visa 3.11.x
poetry --version    # installera via pipx/pip om kommandot saknas
```

## 2. Installera beroenden (första gången)

```bash
cd /home/oden/Wisdom/backend
poetry env use 3.11
poetry install
```

## 3. Skapa `backend/.env`

`app/config.py` läser `backend/.env` först och faller sedan tillbaka på `.env` i repo-roten. Lägg in Supabase-, Stripe-, LiveKit- och JWT-sekret enligt nedan (ersätt platshållarna med riktiga värden **innan** du kör kommandot):

```bash
cat > /home/oden/Wisdom/backend/.env <<'EOF'
# Supabase
DATABASE_URL=postgresql://<supabase-user>:<password>@db.<project>.supabase.co:5432/postgres?sslmode=require
SUPABASE_URL=https://<project>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
SUPABASE_ANON_KEY=<anon-key>

# Applikation
FRONTEND_URL=http://localhost:3000
JWT_SECRET=<random-string-från-openssl-rand-hex-32>

# LiveKit & Stripe
LIVEKIT_API_KEY=<livekit-api-key>
LIVEKIT_API_SECRET=<livekit-api-secret>
LIVEKIT_WS_URL=wss://<livekit-project>.livekit.cloud
STRIPE_SECRET_KEY=<sk_test_xxx>
STRIPE_WEBHOOK_SECRET=<whsec_xxx>

# Media
MEDIA_SIGNING_SECRET=<openssl-rand-hex-32>
MEDIA_SIGNING_TTL_SECONDS=600
LESSON_MEDIA_MAX_BYTES=2147483648
EOF
```

Generera starka värden vid behov:

```bash
openssl rand -hex 32    # JWT_SECRET eller MEDIA_SIGNING_SECRET
```

> Tips: Lägg aldrig riktiga hemligheter i git. Spara dem i 1Password eller använd `direnv` för lokal injection.

## 4. Starta servern i förgrunden

```bash
cd /home/oden/Wisdom/backend
poetry run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

- API:t svarar på `http://127.0.0.1:8000`.
- Swagger/Redoc finns på `/docs` och `/redoc`.
- Uvicorn stoppas med `Ctrl+C`.

## 5. Starta i bakgrunden (valfritt)

```bash
cd /home/oden/Wisdom/backend
nohup poetry run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload > ../backend_uvicorn.log 2>&1 &
tail -f ../backend_uvicorn.log
```

Stoppa processen vid behov:

```bash
lsof -i :8000
kill <PID>
```

## 6. Hälsokontroller

```bash
curl -f http://127.0.0.1:8000/healthz
curl -f http://127.0.0.1:8000/readyz
```

## 7. Vanliga felsökningar

- **Port 8000 används redan**  
  ```bash
  lsof -i :8000
  kill <PID>
  ```
- **Saknad miljövariabel** – kontrollera att nyckeln finns i `backend/.env` (kommentera aldrig ut raderna). Starta om uvicorn efter ändring.
- **Poetry hittar inte Python 3.11** – kör `poetry env use $(which python3.11)` eller installera `python3.11` via `sudo apt install python3.11`.

När servern körs kan Flutter/webb peka mot `http://127.0.0.1:8000` via sina `.env`-filer.

## Testa betalvägg för kursen "Vit Magi"

1. Använd `backend/.env.local` (innehåller test-nycklar och price-id).
2. Kör `stripe listen --forward-to http://127.0.0.1:8000/webhooks/stripe`.
3. Trigga `/checkout/session` med `order_type="vit_magi"` från appen.
4. Slutför testbetalning i Stripe Payment Element.
5. Hämta `GET /api/me/entitlements` → ska lista `"vit_magi"` under `courses`.
