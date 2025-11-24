# Backend-API – Subscription MVP

Den här filen beskriver hur du kör FastAPI-instansen i `app.mvp.main` och hur de centrala endpoints används. Alla endpoints använder JWT Bearer-token från `/auth/login`. Databasen ansluts via Psycopg och återanvänds från huvud-appen, så inga extra beroenden behövs.

## Köra servern

```bash
cd backend
poetry run uvicorn app.mvp.main:app --reload --host 0.0.0.0 --port 8000
```

## Auth

```bash
# Registrera konto
curl -X POST http://127.0.0.1:8000/auth/register \
  -H 'content-type: application/json' \
  -d '{"email":"demo@example.com","password":"secret123","display_name":"Demo"}'

# Logga in
curl -X POST http://127.0.0.1:8000/auth/login \
  -H 'content-type: application/json' \
  -d '{"email":"demo@example.com","password":"secret123"}'

# Hämta profil (kräver Authorization header)
export TOKEN="<ACCESS_TOKEN>"
curl http://127.0.0.1:8000/auth/me -H "Authorization: Bearer ${TOKEN}"
```

## Services & Orders

```bash
# Lista aktiva tjänster
curl 'http://127.0.0.1:8000/services?status=active'

# Skapa order för en tjänst (ersätt service_id)
curl -X POST http://127.0.0.1:8000/orders \
  -H 'Authorization: Bearer '${TOKEN} \
  -H 'content-type: application/json' \
  -d '{"service_id":"<SERVICE_UUID>","amount_cents":15000,"currency":"sek"}'

# Hämta en order
curl -H "Authorization: Bearer ${TOKEN}" http://127.0.0.1:8000/orders/<ORDER_UUID>
```

## Payments / Stripe Checkout

```bash
# Skapa checkout-session (Payment Element / ui_mode=custom klient bygger på URL:en)
curl -X POST http://127.0.0.1:8000/payments/stripe/create-session \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  -d '{"order_id":"<ORDER_UUID>","success_url":"http://localhost:3000/success","cancel_url":"http://localhost:3000/cancel"}'
```

Webhooken körs via Stripe CLI:

```bash
stripe listen --forward-to http://127.0.0.1:8000/payments/webhooks/stripe
```

## Billing-subscriptioner

```bash
# Skapa subskriptionssession (plan_interval = month | year)
curl -X POST http://127.0.0.1:8000/billing/create-subscription \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  -d '{"plan_interval":"month","success_url":"http://localhost:3000/success","cancel_url":"http://localhost:3000/cancel"}'

# Kolla mitt medlemskap
curl http://127.0.0.1:8000/api/me/membership -H "Authorization: Bearer ${TOKEN}"
```

## Feed & SFU

```bash
# Publika aktiviteter
curl http://127.0.0.1:8000/feed

# Hämta LiveKit-token för seminarium
curl -X POST http://127.0.0.1:8000/sfu/token \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  -d '{"seminar_id":"<SEMINAR_UUID>"}'
```

Alla endpoint-implementationer använder asynkrona Psycopg-transaktioner och bor i `backend/app/routes/`. `app.mvp.main` återanvänder samma routers för att ge en kompakt MVP-instans utan admin- eller studioendpoints.
