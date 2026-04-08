# Arbetsplan (1–2 veckor)

## Fas A – Databas & migreringar
- **Delmål**
  - Leverera ny grundmigrering för `app.profiles`, kurser, lektioner, enrollments, services, orders, payments och seminars.
  - Dokumentera FK, index och planerade RLS-policyer.
- **Acceptanskriterier**
  - `backend/migrations/sql/026_subscription_core.sql` är idempotent och kan köras upprepade gånger.
  - `make db.migrate` applicerar migreringen utan fel och `database/schema.sql` speglar strukturen.
- **Risker**
  - Överlapp mot befintliga tabeller ger förvirring.
  - Felaktiga relationer blockerar Supabase-export.
- **Fallback**
  - Använd `create table if not exists` + kommentera RLS-stubs.
  - Lägg hjälpfält för framtida dataflytt innan tabellerna börjar användas.

## Fas B – Backend-API
- **Delmål**
  - Ny FastAPI-app (`app.mvp.main`) med routers för auth, services, orders, payments, feed och SFU-token.
  - JWT-guard via befintliga utiler och transaktioner med psycopg.
- **Acceptanskriterier**
  - Servern startar via `poetry run uvicorn app.mvp.main:app --reload`.
  - Curl mot `/auth/register`, `/auth/login`, `/services`, `/orders`, `/payments/stripe/create-session`, `/feed`, `/sfu/token` ger meningsfulla svar.
- **Risker**
  - Dubbla endpoints med befintligt API.
  - Saknade hemligheter gör att Stripe/LiveKit vägrar.
- **Fallback**
  - Håll MVP-appen som separat FastAPI-instans och dokumentera hur den startas.
  - Mocka externa integrationer i dev och logga tydliga fel.

## Fas C – Flutter-UI uppgradering
- **Delmål**
  - Ny `lib/mvp/` modul med `ApiClient`, miljöhantering och sidor för Home, Profil, Login.
  - Knyt listor för Mina kurser, Vägg och Tjänster till API:t eller dev-stubbar.
- **Acceptanskriterier**
  - `flutter analyze` passerar och `MvpApp` kan köras mot lokal backend.
  - Bas-URL växlar automatiskt mellan `10.0.2.2` (Android emulator) och `127.0.0.1` (övriga).
- **Risker**
  - Påverkar befintlig routing.
  - Tokenlagring i demo krockar med huvudanvändare.
- **Fallback**
  - Håll MVP-komponenter frikopplade från produktionsrouter (egen `MvpApp` entrypoint).
  - Förvara tokens i egen `mvp_auth_token`-nyckel.

## Fas D – Stripe-flöden
- **Delmål**
  - Endpoint för Checkout Session (`ui_mode=custom`) och webhook som uppdaterar `app.payments`/`app.service_orders`.
  - README-snutt med CLI-instruktioner samt testkort, Klarna och PayPal-flöden.
- **Acceptanskriterier**
  - Lokalt flöde bekräftar session och webhook markerar order som `paid`.
  - Dokumentation beskriver hur Stripe CLI forwardas.
- **Risker**
  - Webhook signatur mismatch.
  - Checkout saknar `success_url/cancel_url` i dev.
- **Fallback**
  - Vid fel: logga event payload + permit manual replay.
  - Tillåt fallback till `mode="payment"` tills Payment Element är på plats.

## Fas E – SFU (LiveKit) grund
- **Delmål**
  - `POST /sfu/token` validerar att användare får delta i ett seminarium och returnerar token.
  - Flutter-exempel som ansluter via `livekit_client` med host/deltagarvy.
- **Acceptanskriterier**
  - Token-endpoint nekar obehöriga och loggar audit-event.
  - Flutter-sidan kan koppla upp sig mot mockad LiveKit server.
- **Risker**
  - LiveKit secrets saknas lokalt.
  - Token claims försvagar säkerheten.
- **Fallback**
  - Stöd för statiska mock-tokens i dev.
  - Dokumentera hur man genererar hemligheter och varna i `/sfu/token` om nycklar saknas.

## Fas F – Landningssida, juridik, test & drift
- **Delmål**
  - Static landing under `web/landing/` (Hero, storeknappar, login-länk) + `/privacy`, `/terms`, `/gdpr`.
  - QA-script `scripts/qa_teacher_smoke.py`, pytest-stubbar och Docker-compose + make targets.
  - Supabase-playbook för framtida migrering.
- **Acceptanskriterier**
  - `python scripts/qa_teacher_smoke.py` kör utan oväntade fel (mock Stripe/LiveKit vid behov).
  - `docker compose up` startar Postgres + backend.
  - Playbook listar tydliga steg för att aktivera RLS i Supabase.
- **Risker**
  - Konfig spretar mellan README, docs och compose.
  - Landing blir beroende av bundler som inte finns installerad.
- **Fallback**
  - Leverera ren HTML/CSS utan byggsteg.
  - Dokumentera kommandon i `Makefile` och håll Compose minimal (Postgres + backend).
