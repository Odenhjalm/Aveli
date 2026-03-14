# 🔥 **Codex MEGA-PROMPT — Stripe Connect, Payments, Billing & Marketplace Full Pipeline Repair**

**Uppdrag:**
Granska, reparera, uppdatera och fullständigt stabilisera hela Stripe-integrationen i projektet: Connect onboarding, payouts, dashboard-sync, betalningar, webhooks, products, prices, marketplace-flöden, subscription-flöden och alla backend-/Supabase-databindningar.

Du har full tillgång till projektet, kodbasen och Supabase via MCP.

Du ska agera som **fullstack backend-/infra-utvecklare med Stripe-expertkunskap**.

---

# ✔️ **1. Skanna all Stripe-kod i backend**

Analysera _hela projektet_, särskilt filer som:

- `/backend/app/services/stripe_*`
- `/backend/app/api/stripe/*`
- `/backend/app/core/config.py`
- event-/webhook-handlers
- Connect onboarding endpoints
- Payment Intent creation
- Checkout Session creation (om det finns)
- Subscription-flöden
- Marketplace-flöden (platform fee, transfers, payouts)

Identifiera:

- allt som fungerar
- allt som saknas
- allt som är felkonfigurerat
- allt som är riskabelt (t.ex. cleartext, fel scopes, saknade headers)
- allt som behöver uppdateras pga senaste Stripe-bestämmelser

---

# ✔️ **2. Skanna Supabase-schemat och matcha backendens Stripe-behov**

Hämta allt relevant:

- tabeller för teachers/providers (Connect accounts)
- tabeller för payments, orders, products, prices, invoices
- event-store för Stripe webhooks (om den finns)
- relationer mellan user → teacher → stripe_account →

Notera ALLA avvikelser:

- saknade kolumner
- fel datatyper
- trasiga policies
- migrations som inte kört
- tabeller som inte följer backendens förväntningar

Om backend kräver tabeller men de saknas → planera att skapa dem.

Exempel som ofta krävs:

```
app.stripe_accounts
app.stripe_customers
app.stripe_products
app.stripe_prices
app.orders
app.order_items
app.transactions
```

Du avgör baserat på kodbasens intentioner.

---

# ✔️ **3. Granska och reparera env-konfiguration för Stripe**

Säkerställ att `.env` / settings systemet stöder:

```
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
STRIPE_CONNECT_CLIENT_ID=
STRIPE_CONNECT_REFRESH_URL=
STRIPE_CONNECT_RETURN_URL=
STRIPE_PLATFORM_FEE_PERCENT=
STRIPE_APPLICATION_FEE_FIXED=
STRIPE_SUCCESS_URL=
STRIPE_CANCEL_URL=
```

Om backend saknar nödvändiga variabler:

- lägg till dem i config
- använd repo-standard
- rör inte produktionsnycklar
- skapa `.env.example` uppdatering

---

# ✔️ **4. Reparera Connect Onboarding-flödet**

Se till att:

- läraren får ett Stripe Express Connect-konto
- onboarding-länk genereras korrekt
- refresh/return URLs används
- status uppdateras i Supabase
- kontot valideras via webhook `account.updated`
- utbetalningar är korrekt aktiverade
- backend har fallback för accounts som saknas

Krav:

- hantera onboarding re-entry (om de inte slutför flödet)
- hantera restrictions / requirements_missing
- uppdatera DB-schema om fält saknas, t.ex.:

```
stripe_account_id
charges_enabled
payouts_enabled
details_submitted
requirements_due
```

---

# ✔️ **5. Reparera betalningsflöden (Payment Intent / Checkout Sessions)**

Beror på vad projektet använder.

Analysera backend:

- skapa korrekt Payment Intent
- knyt till customer (om sådan finns)
- skapa price/product och caching i DB
- supportera rabattkoder / kuponger (om projektet anger det)
- refund endpoints (om de finns)

Codex ska:

- laga endpoints
- lägga till felhantering
- skapa migrations om products/prices-tabeller saknas
- validera att betalningar landar i DB efter webhook

---

# ✔️ **6. Reparera Marketplace-flödet (platform fees + transfers)**

Om projektet tillåter lärare att sälja tjänster eller sessions:

1. Kontrollera användning av:

- `transfer_data[destination]`
- `application_fee_amount`
- `application_fee_percent`
- `on_behalf_of`

2. Kontrollera att alla betalningar loggas i DB:

- order
- order_items
- transaction (Stripe charge / intent / balance txn)

3. Kontrollera att payouts triggas korrekt:

- direkt via Stripe (default Connect)
- eller via backend-transfer (om man använder “separate charges & transfers”)

4. Om DB saknar struktur → skapa migrations.

---

# ✔️ **7. Reparera och hårdgöra Stripe webhooks**

Codex ska:

- analysera webhook-endpoints
- stänga säkerhetshål
- validera signaturer med `STRIPE_WEBHOOK_SECRET`
- stödja alla events som backend behöver, t.ex.:

### För Connect:

- `account.updated`
- `account.external_account.created`
- `account.external_account.updated`

### För Payments:

- `payment_intent.succeeded`
- `payment_intent.payment_failed`

### För Checkout Sessions (om det används):

- `checkout.session.completed`

### För Billing (om subscription används):

- `customer.subscription.created`
- `invoice.paid`

Webhook-handler ska:

- uppdatera rätt tabeller i Supabase
- logga data i webhook event-store om projektet använder en sådan tabell
- vara idempotent (ingen double-processing)

---

# ✔️ **8. Lägg till och kör migrations där det behövs**

Där backend förväntar sig tabeller, policies eller kolumner → skapa migrations:

- i `supabase/migrations/`
- följ repo-standard
- inga duplicat
- inga brutna migrations
- inkludera RLS som matchar projektet

När allt är redo:

```
supabase db push
```

Verifiera:

- tabeller finns
- policies är aktiva
- triggers är rätt
- constraints är rätt

---

# ✔️ **9. Kör full integrationstestning**

Starta backend:

```
poetry run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Testa:

- skapa Connect onboarding-länk
- testa att lärare får status i DB
- utför test-betalning med Stripe testmode
- kontrollera webhook-flöden
- kontrollera marketplace-transfer (om projektet använder det)

Codex ska justera kod tills ALLT fungerar.

---

# ✔️ **10. Leverera en full slutrapport**

När Codex är klar ska han ge:

1. en lista med alla problem han hittade
2. alla ändringar han gjort
3. alla migrations han skapade
4. verifiering att backend körs utan fel
5. verifiering att onboarding fungerar
6. verifiering att betalningar fungerar
7. verifiering att Connect-konton synkas korrekt
8. verifiering att marketplace-fees fungerar (om används)
9. verifiering att webhooks är idempotenta
10. rekommendationer för framtida stabilitet

---

# ✔️ **Regler**

- ändra inget orelaterat
- följ projektets befintliga stil
- respektera databasens RLS-struktur
- skriv migrations bara när det är nödvändigt
- gör inga antaganden som inte är förankrade i repots kod
- reparera ALLT backend förväntar sig

---

# **🔥 MÅL:**

- Connect-flödet fungerar **perfekt**
- Betalningar fungerar **stabilt**
- Webhooks fungerar **pålitligt**
- Supabase-schema == backend-schema
- Marketplace-flöden fungerar
- Hela Stripe-stack är redo för produktion
