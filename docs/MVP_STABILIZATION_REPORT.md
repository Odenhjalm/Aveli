# MVP Stabilization Report (Phase 0 Snapshot)

- Branch: `fix/mvp-stabilization` (base `81f0fd3`)
- Snapshot purpose: capture current working tree risk before clean-up and stabilization.

## Git Status Summary

- Modified: 0
- Deleted: 0
- Untracked: 185 (see top-50 list below)

## Top 50 Untracked Items (Grouped)

| # | Path / Group | Notes |
|---|--------------|-------|
| 1 | netlify.toml | Netlify SPA routing/cache baseline missing from git |
| 2 | .netlify/ | Root Netlify metadata; likely build artifact |
| 3 | frontend/.netlify/ | Frontend Netlify state; should be ignored or pruned |
| 4 | frontend/web/_redirects | SPA fallback candidate for Netlify deploy |
| 5 | frontend/build_web_prod.sh | Web build helper script |
| 6 | frontend/scripts/check_web_build.sh | Build verification helper |
| 7 | backend/fly.toml | Fly.io deploy config currently untracked |
| 8 | backend/fly_update_secrets.sh | Fly secrets sync helper |
| 9 | backend/.dockerignore | Docker build hygiene |
| 10 | backend/Makefile | Backend automation entrypoint |
| 11 | backend/app/auth/ | New auth package (needs Supabase-first validation) |
| 12 | backend/app/core/ | Core wiring/config additions |
| 13 | backend/app/observability.py + rate_limit.py | Logging/rate-limit middleware |
| 14 | backend/app/services/backend_session_service.py | Session exchange logic |
| 15 | backend/app/services/checkout_urls.py | Stripe checkout URL composition |
| 16 | backend/app/services/entitlements_service.py | Entitlement enforcement |
| 17 | backend/app/services/products_sync_service.py | Product sync flow |
| 18 | backend/app/services/profile_sync.py | Profile sync pipeline |
| 19 | backend/app/routes/webhooks_stripe_lessons.py | Stripe webhook handling |
| 20 | backend/app/routes/products_sync.py | Product sync routes |
| 21 | backend/app/routes/classroom.py | Classroom routes |
| 22 | backend/app/routes/live_events.py | Live events routes |
| 23 | backend/app/routes/home.py | Home route additions |
| 24 | backend/app/repositories/* (classroom, product_mappings, media_library, welcome_cards) | Data access layers for new domains |
| 25 | backend/scripts/auth_ops.py | Auth operations helper |
| 26 | backend/scripts/prod_set_roles.py | Prod role bootstrap |
| 27 | backend/scripts/test_all.sh | Backend test runner |
| 28 | backend/tests (checkout_confirm_flow, stripe_webhook_states) | Coverage for checkout and Stripe |
| 29 | supabase/migrations/019_order_type_bundle.sql | New migration series starts |
| 30 | supabase/migrations/020_storage_buckets.sql | Storage provisioning |
| 31 | supabase/migrations/021_course_entitlements_and_storage_policies.sql | Entitlement policies |
| 32 | supabase/migrations/022_fix_purchases_and_claim_tokens.sql | Purchase fixes |
| 33 | supabase/migrations/023_aveli_pro_platform.sql | Platform schema |
| 34 | supabase/migrations/024_lesson_pricing.sql | Pricing changes |
| 35 | supabase/migrations/025_live_events.sql | Live events schema |
| 36 | supabase/migrations/026_auth_profile_provider_columns.sql | Auth provider columns |
| 37 | supabase/migrations/027_classroom.sql | Classroom schema |
| 38 | supabase/migrations/028_media_library.sql | Media library schema |
| 39 | supabase/migrations/029_welcome_cards.sql | Welcome cards schema |
| 40 | supabase/migrations/autofix_auth_* batch | Supabase auth autofix scripts |
| 41 | frontend/lib/api/backend_api.dart | Backend API client additions |
| 42 | frontend/lib/env/ | Env resolution for Flutter |
| 43 | frontend/lib/features/auth/presentation/oauth_callback_screen.dart | OAuth callback UI |
| 44 | frontend/lib/features/auth/presentation/auth_callback_screen.dart | Auth callback UI |
| 45 | frontend/lib/features/payments/presentation/stripe_success_callback.dart | Stripe success handling |
| 46 | frontend/lib/features/paywall/application/checkout_flow.dart | Paywall checkout flow |
| 47 | frontend/lib/features/live_events/ | Live events UI |
| 48 | frontend/lib/features/media_library/ | Media library UI |
| 49 | frontend/lib/features/classroom/ | Classroom UI |
| 50 | frontend/lib/features/welcome_cards/ | Welcome cards UI |

## Change Scope: MVP vs Post-MVP

- MVP-required: tighten .gitignore and purge tracked caches; move experiments to `archive/`; fix Flutter font/asset paths and SPA redirects; rebuild `build/web` with correct defines; enforce frontend auth to use only `/auth/session` (+ optional `/auth/me`) and remove any `/auth/oauth` usage; verify Stripe webhook routes and entitlements path; document build/deploy/QA steps.
- Post-MVP: additional backend classroom/live-event/media features beyond core auth/checkout; extended teacher dashboards; deeper localization (ARB set); extra Supabase autofix migrations once vetted; operational scripts beyond deploy-critical (e.g., test harness variations).

## Risks and Rollback Plan

- Risks: untracked auth/backend modules could reintroduce legacy flows; multiple new Supabase migrations may alter production schemas; Netlify/Fly configs currently unmanaged; build artifacts/logs (`.netlify`, `backend_uvicorn.log`) can pollute tree; presence of large untracked surface raises chance of secrets/leaky data if not triaged.
- Rollback/Mitigation: work exclusively on `fix/mvp-stabilization`; stage and commit in small, scoped commits per phase; move experiments to `archive/` instead of deleting; leave Supabase migration application gated until reviewed; keep `build/web` reproducible via documented commands; if a change regresses auth/checkout, revert commit on this branch to `81f0fd3` baseline and redeploy with previous build artifacts.

## Phase 1: Bucketization & Hygiene

- Bucket A (MVP code): backend app modules (`auth/`, `core/`, `observability.py`, `rate_limit.py`); services (session, checkout_urls, classroom_realtime/service, entitlements, live_events, media_library, order_state, products_sync, profile_sync, welcome_cards); routes (classroom, courses_admin, home, live_events, products_sync, studio_music, studio_welcome_cards, teacher_connect, webhooks_stripe_lessons); repositories (classroom, entitlements, live_events, media_library, product_mappings, welcome_cards); backend scripts (auth_ops, env_validate, export_supabase_schema, export_users_md, scripts/ops, prod_* seeds/passwords/roles/users, run_live/run_test, set_test_passwords, start_live/start_test, test_all, test_db_up, test_livekit_webhook_verify, test_livekit_ws, test_social_login_* , test_supabase_preroll); backend tests (auth_email_signup, checkout_confirm_flow, home_welcome_card, lesson_stripe_sync, media_library, smoke_api, stripe_webhook_states, studio_welcome_cards); Supabase migrations `supabase/migrations/006_livekit_webhook_jobs.sql` through `029_welcome_cards.sql` plus `autofix_auth_*`; frontend API/core/env/data layers; frontend features (auth callback pages, classroom, home cards, live_events, media_library, payments/paywall/stripe_success_callback, profile_onboarding, studio pages, teacher dashboards, welcome_cards); localization files (`l10n.yaml`, ARB + generated localizations, shared l10n utils); shared widgets (entitlement_badges, skeleton); frontend tests (helpers, integration checkout routing, unit env/checkout_result, widgets including oauth/paywall/deep_link/components, goldens).
- Bucket B (MVP config): `netlify.toml`, `frontend/web/_redirects`, `frontend/build_web_prod.sh`, `frontend/scripts/check_web_build.sh`, `frontend/run_web.sh`, `frontend/devtools_options.yaml`, `backend/fly.toml`, `backend/fly_update_secrets.sh`, `backend/.dockerignore`, `backend/Makefile`.
- Bucket C (Docs for QA/launch): `README-performance.md`, `docs/AUTH_OPS.md`, `docs/LAUNCH_HARDENING_PROGRESS.md`, `docs/SECURITY_SECRETS.md`, `docs/STRIPE_CHECKOUT_FLOW.md`, `docs/auth_email_flow.md`, `docs/auth_v2_overhaul.md`, `docs/environment_matrix.md`, `docs/inforlaunch.md`, `docs/runbooks.md`, `docs/wordpress_oauth_redirect.md`, `docs/wordpress_stripe_redirects.md`.
- Bucket D (Experiments/prototypes/drafts moved): `archive/experiments/` (moved `codex_output/`, auth/env/schema `ops_reports/`, `backend_ops_reports/`), `archive/drafts/` (`USER_ACCOUNTS.md`, `google_sign_in_tasks.md`, `new_oauth.md`, `task.md`, `localization/en.arb`, `localization/sv.arb`).
- Bucket E (Artifacts/logs/cache to ignore): cleaned `.netlify/` and `frontend/.netlify/`, removed `backend_uvicorn.log`, removed tracked `__pycache__` entries from index, dropped empty `lib/` skeleton; added gitignore entries for `.netlify`, logs, ops reports, codex_output, backend_uvicorn.log, logs/.
- Bucket F (Dangerous leftovers parked): `archive/old_auth/026_profile_provider_fields.sql` (duplicate Supabase migration held out of circulation).

## Phase 2: Web Rendering Progress

- Normalized Flutter asset paths to the standard `assets/` root (fonts + images); updated `pubspec.yaml` assets/fonts and `AppImages` references accordingly.
- Removed legacy empty `en.arb`/`sv.arb` from the l10n folder (now archived) to unblock `flutter pub get`.
- Rebuilt web with `flutter build web --release --dart-define=API_BASE_URL=https://aveli.fly.dev --dart-define=OAUTH_REDIRECT_WEB=https://app.aveli.app/auth/callback`; output present in `frontend/build/web`.
- Verified `build/web/assets/AssetManifest.json` and `FontManifest.json` exist. (Service worker still enumerates `assets/assets/*`; planned follow-up: flatten to `assets/*` if runtime cache mismatch reappears.)
- Netlify SPA config hardened in `netlify.toml`: SPA redirect `/* -> /index.html`, no-cache for `index.html`, `main.dart.js`, `flutter.js`, `flutter_bootstrap.js`, `version.json`; long-cache for `/assets/*` and `/canvaskit/*`.
- Build warnings observed: wasm dry-run incompatibilities for `flutter_secure_storage_web`/`uni_links_web`; MaterialIcons tree-shaking notice (icons still bundled).

## Production Web Render Verification (to prove white-screen fixed)

- Build (from repo root): `cd frontend && flutter build web --release --dart-define=API_BASE_URL=https://aveli.fly.dev --dart-define=OAUTH_REDIRECT_WEB=https://app.aveli.app/auth/callback`
- Deploy prebuilt to Netlify: `cd frontend && netlify deploy --dir=build/web --prod` (site must already be configured)
- Post-deploy checks:
  - Open incognito: https://app.aveli.app/#/login
  - Network tab: `assets/AssetManifest.json` and `assets/FontManifest.json` return 200
  - Console: no “Failed to load font” errors
  - UI renders (no white screen)
