# Aveli Sprintplan (Fas A–F)

## Fas A – Databas & Migreringar
- **Delmål**: Schema `app` etableras med alla kärntabeller, vyer och index. Idempotenta migreringar `.sql` ligger i `backend/migrations/sql/` och kan köras på tom Postgres. Fixtures för utveckling finns.
- **Acceptanskriterier**: `psql -f 001_app_schema.sql` kör utan fel; `SELECT * FROM app.activities_feed` fungerar; `make migrate` uppdaterar lokalt. QA kan seed:a testdata med angivna skript.
- **Risker**: Schema-drift mot befintlig data; felaktiga defaultvärden; saknade FK orsakar 500:or. 
- **Fallback**: Behåll snapshot av tidigare schema i `database/schema.sql`; använd `pg_dump` för rollback; dokumentera manuellt patch-skript om migrering måste backas.

## Fas B – Backend-API
- **Delmål**: FastAPI-projektet exponerar auth, services, orders, payments och seminars-endpoints med JWT-skydd, transaktioner och felhantering. 
- **Acceptanskriterier**: `uvicorn app.main:app --reload` startar; `pytest backend/tests/test_api_smoke.py` passerar; curl-exempel från README svarar med 2xx.
- **Risker**: JWT-expirering utan refresh; race conditions i orders; Stripe-webhooks kräver signaturer.
- **Fallback**: Temporärt mocka externa integrationer (Stripe, LiveKit); slå av webhook-hantering och queue:a events för senare behandling.

## Fas C – Flutter-UI
- **Delmål**: Miljöhantering (10.0.2.2/127.0.0.1), ApiClient och HOME/Profil/Login kopplade mot nya endpoints. 
- **Acceptanskriterier**: `flutter run` mot emulator visar listor (kurser/feed/tjänster); login lagrar token och fetchar `/me`; profiländringar sparas.
- **Risker**: Dio-interceptors orsakar refresh-loopar; state-hantering skapar regressions i Riverpod.
- **Fallback**: Lås `ApiClient` i read-only-läge och visa varnings-banner; tillåt dev att använda mockad backend (`--dart-define USE_STUB_API=false`).

## Fas D – Stripe-flöden
- **Delmål**: `/payments/stripe/create-session` och `/payments/webhooks/stripe` fungerar lokalt. Flutter kan öppna checkout.
- **Acceptanskriterier**: `stripe listen --forward-to http://localhost:8080/payments/webhooks/stripe` med testkort sätter order `paid`; DB-uppdateringar loggas.
- **Risker**: Webhook-signatur mismatch; race i double-processing; currency mismatch SEK/EUR.
- **Fallback**: Queue:a webhookpayloads till fil och kör `scripts/replay_stripe_webhook.py`; fallback till PaymentIntent + manual capture.

## Fas E – SFU (LiveKit)
- **Delmål**: Backend genererar LiveKit-token (`POST /sfu/token`). Flutter-sida använder `livekit_client` för enkel session.
- **Acceptanskriterier**: Lokal LiveKit Cloud-config i `.env`; test i emulator ansluter (mockat WS). Token endpoint validerar seminar-deltagare.
- **Risker**: LiveKit-nätverk blockerad; tokens expirerar för tidigt; mobil mikrofon-behörigheter.
- **Fallback**: Returnera stub-data (dummy ws_url/token) och logga "live mode" flagga; använd inspelad video för demo.

## Fas F – Landningssida, Juridik & Drift
- **Delmål**: Next.js/Astro frontend med hero + storeknappar + juridiska sidor. Docker-compose/Makefile + `.env.example`.
- **Acceptanskriterier**: `npm run dev` startar webapp; `/privacy`, `/terms`, `/gdpr` laddar; `docker compose up` startar stack (pg + backend + web). QA-smoketest uppdaterad.
- **Risker**: CORS mellan web och backend; SEO/metadata saknas; docker-resurser.
- **Fallback**: Statiska HTML-sidor i `web/public`; erbjuda manual run-script i README om compose misslyckas.
