# Inför lansering – checklist (live)

Status: NOT DONE = ❌, DONE = ✅

## Infrastruktur & data
- ❌ [Ägare: DevOps] Miljömatris klar (separat Supabase/Stripe/LiveKit för staging/prod; ingen delad service role)
- ❌ [Ägare: DevOps] Verifiera att Supabase-migreringar körs grönt i staging (`scripts/apply_supabase_migrations.sh`)
- ✅ [Ägare: DB] RLS aktiverad på alla app-tabeller (policies i 008_rls_app_policies.sql)
- ❌ [Ägare: DB] Exportera `supabase/security_definer_export.sql` och `supabase/schema.sql` snapshot
- ❌ [Ägare: DevOps] CORS/origin-listor uppdaterade för backend + Supabase (REST/storage)
- ❌ [Ägare: DevOps] Stripe-webhooks pekar mot prod backend och hemligheter är uppdaterade
- ❌ [Ägare: DevOps] LiveKit webhook och API-nycklar laddade i prod
- ❌ [Ägare: DevOps] Backup-plan (PITR + snapshots) dokumenterad och testad restore

## Backend & API
- ❌ [Ägare: Backend] Prod-konfig i `.env`/`.env.docker` (Supabase URL/keys, Stripe, LiveKit, JWT, media secret)
- ❌ [Ägare: Backend] `/readyz` rapporterar ok mot prod DB
- ❌ [Ägare: Backend] Observabilitet: `/metrics` kopplad till monitorering + Sentry aktiv
- ❌ [Ägare: Backend] CI okej (migrations → pytest → QA smoke → flutter test)
- ❌ [Ägare: Backend] QA-script (`make qa.teacher`) passerar end-to-end mot staging
- ❌ [Ägare: Backend] Rate limits/missbruksskydd på auth/billing/media-endpoints

## Betalning & LiveKit
- ❌ [Ägare: Backend] Stripe-prod: webhooks, `STRIPE_*` roterade, pris-ID matchar app, kvitto/avbokning testat
- ❌ [Ägare: Backend] LiveKit-prod: API-nycklar/webhook-sekret laddade, `app.livekit_webhook_jobs`-kö och policy på plats
- ❌ [Ägare: Backend] Larm på Stripe/LiveKit-webhookfel och webhook-replay/runbook dokumenterad

## Frontend / Flutter / Web
- ❌ [Ägare: Frontend] Prod `API_BASE_URL`, Supabase anon URL/key och feature-flaggor på plats (web + mobil)
- ❌ [Ägare: Frontend] Flutter release-build signerad och testad (web + Android/iOS)
- ❌ [Ägare: Frontend] Next.js-landing: prod-env/domän satt, `npm run build` grönt, SEO/analytics aktiverat
- ❌ [Ägare: Frontend] Offline/edge-cases verifierade (token refresh, nätverksfel)

## CI/CD & Release
- ❌ [Ägare: DevOps] CI-pipeline kör migrations → pytest → QA-smoke → `flutter test`; artefakter signeras
- ❌ [Ägare: DevOps] Release-branch/taggning + protections för main
- ❌ [Ägare: DevOps] Docker/Vercel deployer använder prod-hemligheter via env, inte filer
- ❌ [Ägare: DevOps] Staging-genomgång körd: `make supabase.migrate && make backend.test && make qa.teacher && flutter test` (loggar sparade)
- ❌ [Ägare: DevOps] Prod-smokeplan + rollback/feature-flag-strategi för cutover

## Dokumentation & säkerhet
- ❌ [Ägare: Security] Hemligheter roterade (Supabase/Stripe/LiveKit/JWT/webhooks) och endast i secrets-hanterare, inte i repo
- ✅ [Ägare: Docs] README/backend README/local backend setup uppdaterade (Supabase-first)
- ❌ [Ägare: Docs] Återstående legacy-dokument arkiverade eller rensade
- ❌ [Ägare: Docs] Support- och driftinstruktioner distribuerade till teamet
- ❌ [Ägare: Security] Secrets roterade (Supabase service role, Stripe, LiveKit, JWT) och rotationsplan sparad
- ❌ [Ägare: Security] Pen-test/light threat model: auth/billing/media + dependency audits

## Drift & Support
- ❌ [Ägare: Ops] Runbooks i `docs/` (incident, backup-restore, webhook-kö, betalningsåterställning)
- ❌ [Ägare: Ops] Larm/trösklar: felrate API, webhook-kö, DB-anslutningar, 5xx i frontend
- ❌ [Ägare: Ops] On-call/ägarlista och supportprocess (betalningsproblem/kontospärr)
- ❌ [Ägare: Ops] Kapacitets-/prestandatest (Supabase connections, API throughput, CDN/cache)

## Go/No-Go
- ❌ [Ägare: Produkt] Produkts QA-signoff
- ❌ [Ägare: DevOps] Drift/DevOps signoff
- ❌ [Ägare: DevOps] Backup/restore-plan verifierad

Uppdatera status fortlöpande när punkter blir klara.
