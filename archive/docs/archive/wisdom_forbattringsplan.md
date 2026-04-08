# Wisdom – förbättringsrekommendationer och arbetsplan

## Översikt
- Projektet är välstrukturerat men har flera säkerhets- och underhållsrisker som bör adresseras innan ny funktionalitet prioriteras.
- Den lokala backend-stackens SQL och dokumentation har drivit isär, vilket ökar risken för driftfel och onödig felsökning.
- Flutter-klient och backend delar ingen gemensam typdefinition, vilket leder till `Map<String, dynamic>`-hantverk och sämre felupptäckt.
- QA-flödet är gediget men saknar täckning för kritiska betalnings- och SFU-scenarier när Stripe/LiveKit inte är korrekt konfigurerade.

## Prioriterade förbättringsområden
1. **Sanera läckta hemligheter och standardisera konfiguration**
   - Problem: Konfigurationsfiler och scripts har tidigare innehållit riktiga inloggningsuppgifter, vilket skapar risk för läckage och felaktig produktionsexport.
   - Åtgärder:
     - Ersätt känsliga strängar med platshållare och dokumentera hur `.env.local` genereras.
     - Lägg till `dotenv-linter`/pre-commit check för att förhindra framtida misstag.
     - Lägg credentials i en krypterad `1password`/`pass`-vault och länka från dokumentation.

2. **Konsolidera databasdefinitioner och migreringsflöden**
   - Problem: Två parallella källor (`database/schema.sql` + `database/migrations/` kontra `backend/migrations/sql/`) riskerar divergens; scripts kör båda vilket förlänger provisioneringstiden.
   - Åtgärder:
     - Välj en ensam sanning (rekommenderat: `backend/migrations/sql` som versioneras) och låt övriga filer genereras automatiskt.
     - Inför ett enkelt checksum-test i CI som larmar om schema/migrationer inte matchar.
     - Dokumentera i `docs/local_backend_setup.md` hur migreringar körs via `make db.migrate`.

3. **Modularisera backendens data- och domänlager**
   - Problem: `backend/app/models.py` (~800 rader) blandar media, auth, betalningar, community, tarots etc. vilket gör testbarhet och typannotering svår.
   - Åtgärder:
     - Bryt ut modulespecifika repositories (`profiles_repository.py`, `payments_repository.py` osv) och infoga TypedDict/Pydantic-svar.
     - Lägg in service-nivå med transaktionshantering per domän för att minska duplicerad felhantering.
     - Skapa mappspecifika pytest-fixtures för respektive modul så att regressioner fångas snabbare.

4. **Stärk API-kontraktet mellan backend och Flutter**
   - Problem: Flera repositories i Flutter (t.ex. `lib/features/payments/data/payments_repository.dart`) hanterar råa `Map<String, dynamic>` och saknar automatiserade kontraktstester.
   - Åtgärder:
     - Introducera `json_serializable`-baserade modeller i `lib/api/models/` och använd dem i repositories.
     - Generera en OpenAPI-spec från FastAPI (`app/main.py`) och kör den mot Dart via `openapi-generator` för att upptäcka brytande ändringar.
     - Lägg enkla schema/kontrakts-tester i backend (t.ex. `pytest --openapi`) som CI-krav.

5. **Höj observabilitet och felrapportering**
   - Problem: FastAPI saknar strukturerad loggning, rate limiting och korrelation mellan request-id och Stripe/LiveKit-händelser; Flutter saknar konsistent feltelemetri.
   - Åtgärder:
     - Lägg till `structlog`/`loguru` och korrelera request-id via middleware; skicka vidare till Stripe-webhookarna.
     - Exponera health-/metrics-endpoints (Prometheus) för senare drift.
     - Konfigurera Firebase Crashlytics/Firebase Analytics så att auth- och betalningsfel taggas med backend response codes.

6. **Rensa repo och förbättra dokumentationshygienen**
   - Problem: Backups och loggar ligger versionerade (`backup/wisdom_dump_20251008_155345.sql`, `backend_uvicorn.log`), `.gitignore` innehåller kvarlämnat `EOF`, och dokument refererar fortfarande till "Visdom".
   - Åtgärder:
     - Flytta dump/loggfiler till artefaktkatalog utanför git; uppdatera `.gitignore`.
     - Städa dokumentation för konsekvent namngivning, lägg till en "Getting Started" som täcker både Docker och manuell setup.
     - Lägg ett `docs/changelog.md`-kapitel för backend/Flutter så nya teammedlemmar ser senaste förändringar.

7. **Komplettera test- och QA-flöden**
   - Problem: Pytest saknar scenarier för ogiltiga Stripe-signaturer, LiveKit-konfigurationsfel och community-follow-kantfall. Fluttertester fokuserar på UI-rendering men inte API-fel.
   - Åtgärder:
     - Lägg negativa tests i `backend/tests/test_api_smoke.py` och modulvisa tester för `community_follow`-begränsningar.
     - Utöka `scripts/qa_teacher_smoke.py` med asserts för playlist/meditationer och fallback när Stripe inte svarar.
     - Skapa Flutter integrationstester som mockar `ApiClient`-fel (401/409/503) för att validera feltoast och tokenrotation.

## Övriga rekommendationer
- Skärp `analysis_options.yaml` (aktivera `prefer_const_constructors`, `strict-raw-types`, `avoid_dynamic_calls`) för att minska runtime-fel.
- Lägg till `ruff` eller `flake8` + `mypy` i backend CI och skapa en `pre-commit` konfiguration som kör formatters/lints innan commit.
- Dokumentera Stripe/LiveKit sandbox-nycklar i ett separat README och länka till testkortslistor.
- Säkerställ att `Makefile` kommandon fungerar på alla plattformar (ersätt `@cd web && npm install` med `npm ci` och kontrollerad Node-version via `volta` eller `.nvmrc`).

## Föreslagen arbetsplan (3 sprintar à ~1 vecka)
### Sprint 1 – Konfiguration & säkerhet
- Sanera alla exempel/scripter från hårdkodade hemligheter och uppdatera dokumentation.
- Lägg till `pre-commit` (dotenv-linter, ruff/flake8, dart format, flutter analyze).
- Skapa pipeline-checks för att säkerställa att `.env.example` inte innehåller känsliga värden.

### Sprint 2 – Backend & databas
- Konsolidera migrationskedjan och migrera `models.py` till moduluppdelade repositories.
  - Skapa `backend/app/repositories/` med domänfiler (`auth.py`, `profiles.py`, `payments.py`, `community.py`, `courses.py`).
  - Låt `backend/app/models.py` exportera funktioner från respektive modul under en övergångsperiod för bakåtkompatibilitet.
  - Uppdatera routers/tests successivt till att importera från de nya modulerna och ta bort duplicerad logik.
  - ✅ Första steget klart: auth-, profil-, order- och betalningsfunktioner bryts ut och `models.py` delegerar till `repositories/`.
- Inför service-lager med typer samt lägg till nya pytest-scenarier (Stripe fel, LiveKit, community follows).
  - Introducera `services/`-nivå med transaktionskontroll + TypedDict-svar.
  - Lägg negativa tester för Stripe-signatur och LiveKit-misskonfiguration i `backend/tests/`.
- Generera och publicera OpenAPI-spec; skapa kontraktstest i CI.

### Sprint 3 – Klient & observabilitet
- Implementera typed modeller i Flutter + uppdaterade integrationstester för felvägar.
- Lägg till strukturerad loggning, request-id middleware och Prometheus-endpoints i FastAPI.
- Uppdatera Crashlytics/Analytics-integrationer och säkerställ att QA-script täcker Stripe/LiveKit fallback-scenarier.
