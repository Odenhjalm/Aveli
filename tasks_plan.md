# Arbetsplan – Aveli

Checklistan samlar pågående och kommande uppgifter. Bocka i `[]` när en punkt är klar.

## 1. QA & Felsökning
- [x] Samla Android‑emulatorloggar (`flutter run --verbose`, `adb logcat`) och summera 404/401/cleartext-fynd i `docs/image_inventory.md`.

## 2. Security Definer & DB-härdning
- [x] Inventera alla `SECURITY DEFINER`-funktioner i `database/schema.sql` + migreringar.
- [x] Uppdatera funktioner att sätta `SECURITY DEFINER SET search_path = app, public`.
- [x] Infoga `uid uuid := auth.uid();` (eller motsv.) samt rollkontroller i varje funktion.
- [x] Ersätt dynamisk SQL med parametriserade `EXECUTE ... USING`.
- [x] Exportera aktuell lista och dokumentera i `docs/security_definer_audit.md`.

## 3. Media & Buckets
- [x] Bekräfta att bucket `media` bara innehåller publikt innehåll; dokumentera i README.
- [x] Skapa privat bucket för lektionsmedia och uppdatera backend att lagra där.
- [x] Lägg TTL + `Content-Disposition` på signerade svar och skriv tester.
- [x] Implementera direktuppladdningar (presigned URLs) och klientflöden för dem.

## 4. CI & Secrets
- [x] Flytta känsliga variabler till GitHub Secrets och lista dem per workflow.
- [x] Se över `.env.ci.*` och sätt upp injicering i CI-pipelines.

## 5. Observability & Plattform
- [x] Aktivera Sentry i Flutter, FastAPI och Next.js (DSN via config) + verifiera events.
- [x] Lägg till strukturerad loggning i backend (request-id/user-id).
- [ ] Exponera health- och readiness-endpoints i FastAPI och täck med tester.
- [x] Aktivera GZip/Brotli samt HTTP/2/3 och sätt korrekt CORS-whitelist.
- [x] Lägg Prometheus-metrik för live sessions (om ej redan i drift).

## 6. RLS & Policies
- [x] Kör full RLS-revision per tabell – särskilt publika `SELECT`-policys.
- [x] Verifiera lärarbehörigheter mot affärskrav och justera policys.
- [x] Dokumentera policy-matrisen i `docs/` (ex. `rls_policies.csv`).

## 7. Dokumentation & Konfiguration
- [x] Uppdatera README med make-mål och e2e-flödesguide (login → köp → kurs).
- [x] Implementera Pydantic-baserade settings per miljö i backend.
- [x] Synka `.env.example` för Flutter, web och backend med alla aktuella nycklar.
