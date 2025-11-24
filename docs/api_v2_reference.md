# Aveli API v2 – Snabbguide

Samtliga kommandon utgår från att backenden körs lokalt på `http://localhost:8000` och att du redan har startat Postgres (`make db.up`), kört migreringar (`make db.migrate`) samt seed (`make db.seed`).

> **Token**: Spara `access_token` från `/auth/login` eller `/auth/register` i en shell-variabel, t.ex. `TOKEN=$(...)`.

## Auth

```bash
# Registrera konto
curl -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@aveli.dev","password":"changeme","display_name":"Demo"}'

# Logga in
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@aveli.dev","password":"changeme"}'

# Hämta profil
curl http://localhost:8000/auth/me \
  -H "Authorization: Bearer $TOKEN"

# Uppdatera profilnamn
curl -X PATCH http://localhost:8000/auth/me \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"display_name":"Soul Seeker"}'

# Ladda upp avatar
curl -X POST http://localhost:8000/auth/me/avatar \
  -H "Authorization: Bearer $TOKEN" \
  -F file=@/path/till/avatar.png

# Rotera tokens
curl -X POST http://localhost:8000/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token":"<refresh>"}'
```

## Tjänster och orders

```bash
# Lista aktiva tjänster
curl http://localhost:8000/services?status=active

# Skapa order för en tjänst
curl -X POST http://localhost:8000/orders \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"service_id":"66666666-6666-4666-8666-666666666666"}'

# Hämta order
curl http://localhost:8000/orders/77777777-7777-4777-8777-777777777777 \
  -H "Authorization: Bearer $TOKEN"
```

## Stripe

```bash
# Skapa checkout-session
curl -X POST http://localhost:8000/payments/stripe/create-session \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "order_id":"77777777-7777-4777-8777-777777777777",
        "success_url":"https://example.org/success",
        "cancel_url":"https://example.org/cancel"
      }'

# Webhook (via Stripe CLI)
stripe listen --forward-to http://localhost:8000/payments/webhooks/stripe
```

## Aktivitetsflöde

```bash
curl http://localhost:8000/feed?limit=20 \
  -H "Authorization: Bearer $TOKEN"
```

## SFU / LiveKit

```bash
curl -X POST http://localhost:8000/sfu/token \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"seminar_id":"99999999-9999-4999-8999-999999999999"}'
```

Sätt `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` och `LIVEKIT_WS_URL` i `.env` innan du anropar endpointen. Utan dessa värden svarar servern med `503`, vilket klienten kan använda för att falla tillbaka till ett mockat videoflöde under utveckling.

Felsvar:
- `404` om seminariet saknas eller ingen session är schemalagd.
- `403` när användaren saknar behörighet (ej host eller registrerad deltagare).
- `409` när sessionen redan är avslutad.
