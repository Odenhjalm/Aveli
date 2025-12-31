# Launch Readiness Report

Status: NOT READY (backend/.env missing + test/build blockers)

## Pass/Fail Matrix
| Area | Status | Notes |
| --- | --- | --- |
| Env guard (backend/.env not tracked) | PASS | guardrails active |
| Env validation | FAIL | backend/.env missing |
| Env contract check | FAIL | backend/.env missing |
| Stripe test verification | FAIL | backend/.env missing |
| Supabase env verification | FAIL | backend/.env missing |
| Remote DB read-only verify | SKIP | SUPABASE_DB_URL/DATABASE_URL not set |
| RLS enabled for app tables | SKIP | remote DB verify not run |
| RLS policies present | SKIP | remote DB verify not run |
| Storage buckets + policies | SKIP | remote DB verify not run |
| Backend tests | FAIL | backend/.env missing (config raises) |
| Backend smoke (Stripe checkout + membership) | FAIL | backend could not start |
| Flutter tests | FAIL | unit tests pass; integration tests fail on linux device |
| Landing tests | PASS | vitest ok |
| Landing build | FAIL | missing `@sentry/nextjs` |

## Fixes Applied
- Backend config now loads only `backend/.env` and fails fast if missing; repo guardrails block committing env files.
- Added `ENV_REQUIRED_KEYS.txt` + `backend/scripts/env_contract_check.py` and wired into `ops/verify_all.sh`.
- Added `backend/scripts/stripe_verify_test_mode.py` and `backend/scripts/supabase_verify_env.py`.
- Updated backend env templates/docs to use `backend/.env` only and include QA/import keys.
- `ops/verify_all.sh` installs deps (Poetry/NPM) and auto-selects Flutter devices; remote DB verify loads `backend/.env` and uses the allowlist.

## Remaining Blockers
- `backend/.env` missing in the clean worktree (blocks env checks, Stripe/Supabase verify, backend tests/smoke).
- Remote DB verify still needs `SUPABASE_DB_URL`/`DATABASE_URL` to run read-only checks.
- Flutter integration tests fail on `FLUTTER_DEVICE=linux` (app fails to start / no debug connection).
- Landing build blocked by missing `@sentry/nextjs`.

## Verification Runs
- Local verify_all (FLUTTER_DEVICE=linux): FAILED (env missing; backend tests/smoke failed; Flutter integration failed; landing build failed)
- Remote DB verify: SKIPPED (SUPABASE_DB_URL/DATABASE_URL not set)

## Next 5 Actions
1. Create `backend/.env` from `backend/.env.example` (test keys only) and re-run `ops/env_validate.sh`.
2. Re-run `backend/scripts/env_contract_check.py`, `stripe_verify_test_mode.py`, and `supabase_verify_env.py`.
3. Export `SUPABASE_DB_URL` (read-only) and rerun `ops/db_verify_remote_readonly.sh`.
4. Fix Flutter integration test environment for linux (device availability + required runtime env).
5. Add `@sentry/nextjs` to `frontend/landing/package.json` or gate Sentry init for builds.

## Remote DB Verify (read-only)
Status: SKIPPED
Reason: SUPABASE_DB_URL/DATABASE_URL not set

## Verification Run (ops/verify_all.sh)
- Env validation: PASS (warnings only)
- Remote DB verify: SKIP
- Local DB reset: SKIP
- Backend tests: FAIL
- Backend smoke: FAIL
- Flutter tests: FAIL
- Landing tests: PASS
- Landing build: FAIL

## Remote DB Verify (read-only)
Status: SKIPPED
Reason: SUPABASE_PROJECT_REF not set and SUPABASE_URL not provided

## Remote DB Verify (read-only)
Status: SKIPPED
Reason: SUPABASE_PROJECT_REF not set and SUPABASE_URL not provided

## Remote DB Verify (read-only)
Status: SKIPPED
Reason: SUPABASE_PROJECT_REF not set and SUPABASE_URL not provided

## Verification Run (ops/verify_all.sh)
- Env guard (backend/.env not tracked): PASS
- Env validation: FAIL
- Env contract check: FAIL
- Stripe test verification: FAIL
- Supabase env verification: FAIL
- Remote DB verify: SKIP
- Local DB reset: SKIP
- Backend tests: FAIL
- Backend smoke: FAIL
- Flutter tests: FAIL
- Landing tests: PASS
- Landing build: FAIL

## Remote DB Verify (read-only)
Status: COMPLETED
- App tables: 57
- RLS disabled tables: live_event_registrations
live_events
- Tables without policies: live_event_registrations
live_events
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=false)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: public-media should be public
- Migration tracking: schema_migrations present
- Migrations missing in DB: 001_app_schema.sql
002_teacher_catalog.sql
003_sessions_and_orders.sql
004_memberships_billing.sql
005_course_entitlements.sql
005_livekit_webhook_jobs.sql
006_course_pricing.sql
006_seminar_sessions.sql
007_rls_policies.sql
008_add_next_run_at_to_livekit_webhook_jobs.sql
008_rls_app_policies.sql
010_fix_livekit_job_id.sql
011_seminar_host_helper.sql
012_seminar_access_wrapper.sql
013_seminar_attendee_wrapper.sql
014_seminar_host_guard.sql
015_profile_stripe_customer.sql
016_course_bundles.sql
017_order_type_bundle.sql
018_storage_buckets.sql
202511180129_sync_livekit_webhook_jobs.sql
- Migrations extra in DB: 027_classroom
028_media_library
029_welcome_cards
add_next_run_at_to_livekit_webhook_jobs
app_schema
auth_profile_provider_columns
aveli_pro_platform
course_bundles
course_entitlements
course_entitlements_and_storage_policies
course_pricing
fix_livekit_job_id
fix_purchases_and_claim_tokens
lesson_pricing
live_events
livekit_webhook_jobs
memberships_billing
order_type_bundle
profile_stripe_customer
rls_app_policies
rls_policies
seminar_access_wrapper
seminar_attendee_wrapper
seminar_host_guard
seminar_host_helper
seminar_sessions
sessions_and_orders
storage_buckets
sync_livekit_webhook_jobs
teacher_catalog

## Remote DB Verify (read-only)
Status: COMPLETED
- App tables: 57
- RLS disabled tables: live_event_registrations
live_events
- Tables without policies: live_event_registrations
live_events
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=false)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: public-media should be public
- Migration tracking: schema_migrations present
- Migrations missing in DB: 001_app_schema.sql
002_teacher_catalog.sql
003_sessions_and_orders.sql
004_memberships_billing.sql
005_course_entitlements.sql
005_livekit_webhook_jobs.sql
006_course_pricing.sql
006_seminar_sessions.sql
007_rls_policies.sql
008_add_next_run_at_to_livekit_webhook_jobs.sql
008_rls_app_policies.sql
010_fix_livekit_job_id.sql
011_seminar_host_helper.sql
012_seminar_access_wrapper.sql
013_seminar_attendee_wrapper.sql
014_seminar_host_guard.sql
015_profile_stripe_customer.sql
016_course_bundles.sql
017_order_type_bundle.sql
018_storage_buckets.sql
202511180129_sync_livekit_webhook_jobs.sql
- Migrations extra in DB: 027_classroom
028_media_library
029_welcome_cards
add_next_run_at_to_livekit_webhook_jobs
app_schema
auth_profile_provider_columns
aveli_pro_platform
course_bundles
course_entitlements
course_entitlements_and_storage_policies
course_pricing
fix_livekit_job_id
fix_purchases_and_claim_tokens
lesson_pricing
live_events
livekit_webhook_jobs
memberships_billing
order_type_bundle
profile_stripe_customer
rls_app_policies
rls_policies
seminar_access_wrapper
seminar_attendee_wrapper
seminar_host_guard
seminar_host_helper
seminar_sessions
sessions_and_orders
storage_buckets
sync_livekit_webhook_jobs
teacher_catalog

## Verification Run (ops/verify_all.sh)
- Env guard (backend/.env not tracked): PASS
- Env validation: PASS
- Env contract check: FAIL
- Stripe test verification: FAIL
- Supabase env verification: FAIL
- Remote DB verify: FAIL
- Local DB reset: SKIP
- Backend tests: FAIL
- Backend smoke: FAIL
- Flutter tests: FAIL
- Landing tests: PASS
- Landing build: FAIL

## Remote DB Verify (read-only)
Status: COMPLETED
- App tables: 57
- RLS disabled tables: live_event_registrations
live_events
- Tables without policies: live_event_registrations
live_events
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=false)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: public-media should be public
- Migration tracking: schema_migrations present
- Migrations missing in DB: 001_app_schema.sql
002_teacher_catalog.sql
003_sessions_and_orders.sql
004_memberships_billing.sql
005_course_entitlements.sql
005_livekit_webhook_jobs.sql
006_course_pricing.sql
006_seminar_sessions.sql
007_rls_policies.sql
008_add_next_run_at_to_livekit_webhook_jobs.sql
008_rls_app_policies.sql
010_fix_livekit_job_id.sql
011_seminar_host_helper.sql
012_seminar_access_wrapper.sql
013_seminar_attendee_wrapper.sql
014_seminar_host_guard.sql
015_profile_stripe_customer.sql
016_course_bundles.sql
017_order_type_bundle.sql
018_storage_buckets.sql
202511180129_sync_livekit_webhook_jobs.sql
- Migrations extra in DB: 027_classroom
028_media_library
029_welcome_cards
add_next_run_at_to_livekit_webhook_jobs
app_schema
auth_profile_provider_columns
aveli_pro_platform
course_bundles
course_entitlements
course_entitlements_and_storage_policies
course_pricing
fix_livekit_job_id
fix_purchases_and_claim_tokens
lesson_pricing
live_events
livekit_webhook_jobs
memberships_billing
order_type_bundle
profile_stripe_customer
rls_app_policies
rls_policies
seminar_access_wrapper
seminar_attendee_wrapper
seminar_host_guard
seminar_host_helper
seminar_sessions
sessions_and_orders
storage_buckets
sync_livekit_webhook_jobs
teacher_catalog

## Verification Run (ops/verify_all.sh)
- APP_ENV: development (dev)
- Skipped checks: Local DB reset
- Env guard (backend/.env not tracked): PASS
- Env validation: PASS
- Env contract check: PASS
- Stripe test verification: FAIL
- Supabase env verification: FAIL
- Remote DB verify: FAIL
- Local DB reset: SKIP
- Backend tests: FAIL
- Backend smoke: FAIL
- Flutter tests: FAIL
- Landing tests: PASS
- Landing build: PASS

## Remote DB Verify (read-only)
Status: COMPLETED
- App tables: 57
- RLS disabled tables: live_event_registrations
live_events
- Tables without policies: live_event_registrations
live_events
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=false)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: public-media should be public
- Migration tracking: schema_migrations present
- Migrations missing in DB: 001_app_schema.sql
002_teacher_catalog.sql
003_sessions_and_orders.sql
004_memberships_billing.sql
005_course_entitlements.sql
005_livekit_webhook_jobs.sql
006_course_pricing.sql
006_seminar_sessions.sql
007_rls_policies.sql
008_add_next_run_at_to_livekit_webhook_jobs.sql
008_rls_app_policies.sql
010_fix_livekit_job_id.sql
011_seminar_host_helper.sql
012_seminar_access_wrapper.sql
013_seminar_attendee_wrapper.sql
014_seminar_host_guard.sql
015_profile_stripe_customer.sql
016_course_bundles.sql
017_order_type_bundle.sql
018_storage_buckets.sql
202511180129_sync_livekit_webhook_jobs.sql
- Migrations extra in DB: 027_classroom
028_media_library
029_welcome_cards
add_next_run_at_to_livekit_webhook_jobs
app_schema
auth_profile_provider_columns
aveli_pro_platform
course_bundles
course_entitlements
course_entitlements_and_storage_policies
course_pricing
fix_livekit_job_id
fix_purchases_and_claim_tokens
lesson_pricing
live_events
livekit_webhook_jobs
memberships_billing
order_type_bundle
profile_stripe_customer
rls_app_policies
rls_policies
seminar_access_wrapper
seminar_attendee_wrapper
seminar_host_guard
seminar_host_helper
seminar_sessions
sessions_and_orders
storage_buckets
sync_livekit_webhook_jobs
teacher_catalog

## Verification Run (ops/verify_all.sh)
- APP_ENV: development (dev)
- Skipped checks: Local DB reset
- Env guard (backend/.env not tracked): PASS
- Env validation: PASS
- Env contract check: PASS
- Stripe test verification: FAIL
- Supabase env verification: PASS
- Remote DB verify: FAIL
- Local DB reset: SKIP
- Backend tests: FAIL
- Backend smoke: FAIL
- Flutter tests: FAIL
- Landing tests: PASS
- Landing build: PASS

## Remote DB Verify (read-only)
Status: COMPLETED
- App tables: 57
- RLS disabled tables: live_event_registrations
live_events
- Tables without policies: live_event_registrations
live_events
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=false)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: public-media should be public
- Migration tracking: schema_migrations present
- Migrations missing in DB: 001_app_schema.sql
002_teacher_catalog.sql
003_sessions_and_orders.sql
004_memberships_billing.sql
005_course_entitlements.sql
005_livekit_webhook_jobs.sql
006_course_pricing.sql
006_seminar_sessions.sql
007_rls_policies.sql
008_add_next_run_at_to_livekit_webhook_jobs.sql
008_rls_app_policies.sql
010_fix_livekit_job_id.sql
011_seminar_host_helper.sql
012_seminar_access_wrapper.sql
013_seminar_attendee_wrapper.sql
014_seminar_host_guard.sql
015_profile_stripe_customer.sql
016_course_bundles.sql
017_order_type_bundle.sql
018_storage_buckets.sql
202511180129_sync_livekit_webhook_jobs.sql
- Migrations extra in DB: 027_classroom
028_media_library
029_welcome_cards
add_next_run_at_to_livekit_webhook_jobs
app_schema
auth_profile_provider_columns
aveli_pro_platform
course_bundles
course_entitlements
course_entitlements_and_storage_policies
course_pricing
fix_livekit_job_id
fix_purchases_and_claim_tokens
lesson_pricing
live_events
livekit_webhook_jobs
memberships_billing
order_type_bundle
profile_stripe_customer
rls_app_policies
rls_policies
seminar_access_wrapper
seminar_attendee_wrapper
seminar_host_guard
seminar_host_helper
seminar_sessions
sessions_and_orders
storage_buckets
sync_livekit_webhook_jobs
teacher_catalog

## Verification Run (ops/verify_all.sh)
- APP_ENV: development (dev)
- Skipped checks: Local DB reset
- Env guard (backend/.env not tracked): PASS
- Env validation: PASS
- Env contract check: PASS
- Stripe test verification: PASS
- Supabase env verification: PASS
- Remote DB verify: FAIL
- Local DB reset: SKIP
- Backend tests: PASS
- Backend smoke: FAIL
- Flutter tests: FAIL
- Landing tests: PASS
- Landing build: PASS

## Remote DB Verify (read-only)
Status: COMPLETED
- App tables: 57
- RLS disabled tables: live_event_registrations
live_events
- Tables without policies: live_event_registrations
live_events
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=false)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: public-media should be public
- Migration tracking: schema_migrations present
- Migrations missing in DB: 001_app_schema.sql
002_teacher_catalog.sql
003_sessions_and_orders.sql
004_memberships_billing.sql
005_course_entitlements.sql
005_livekit_webhook_jobs.sql
006_course_pricing.sql
006_seminar_sessions.sql
007_rls_policies.sql
008_add_next_run_at_to_livekit_webhook_jobs.sql
008_rls_app_policies.sql
010_fix_livekit_job_id.sql
011_seminar_host_helper.sql
012_seminar_access_wrapper.sql
013_seminar_attendee_wrapper.sql
014_seminar_host_guard.sql
015_profile_stripe_customer.sql
016_course_bundles.sql
017_order_type_bundle.sql
018_storage_buckets.sql
202511180129_sync_livekit_webhook_jobs.sql
- Migrations extra in DB: 027_classroom
028_media_library
029_welcome_cards
add_next_run_at_to_livekit_webhook_jobs
app_schema
auth_profile_provider_columns
aveli_pro_platform
course_bundles
course_entitlements
course_entitlements_and_storage_policies
course_pricing
fix_livekit_job_id
fix_purchases_and_claim_tokens
lesson_pricing
live_events
livekit_webhook_jobs
memberships_billing
order_type_bundle
profile_stripe_customer
rls_app_policies
rls_policies
seminar_access_wrapper
seminar_attendee_wrapper
seminar_host_guard
seminar_host_helper
seminar_sessions
sessions_and_orders
storage_buckets
sync_livekit_webhook_jobs
teacher_catalog

## Remote DB Verify (read-only)
Status: COMPLETED
- App tables: 57
- RLS disabled tables: live_event_registrations
live_events
- Tables without policies: live_event_registrations
live_events
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=false)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: public-media should be public
- Migration tracking: schema_migrations present
- Migrations missing in DB: 001_app_schema.sql
002_teacher_catalog.sql
003_sessions_and_orders.sql
004_memberships_billing.sql
005_course_entitlements.sql
005_livekit_webhook_jobs.sql
006_course_pricing.sql
006_seminar_sessions.sql
007_rls_policies.sql
008_add_next_run_at_to_livekit_webhook_jobs.sql
008_rls_app_policies.sql
010_fix_livekit_job_id.sql
011_seminar_host_helper.sql
012_seminar_access_wrapper.sql
013_seminar_attendee_wrapper.sql
014_seminar_host_guard.sql
015_profile_stripe_customer.sql
016_course_bundles.sql
017_order_type_bundle.sql
018_storage_buckets.sql
202511180129_sync_livekit_webhook_jobs.sql
- Migrations extra in DB: 027_classroom
028_media_library
029_welcome_cards
add_next_run_at_to_livekit_webhook_jobs
app_schema
auth_profile_provider_columns
aveli_pro_platform
course_bundles
course_entitlements
course_entitlements_and_storage_policies
course_pricing
fix_livekit_job_id
fix_purchases_and_claim_tokens
lesson_pricing
live_events
livekit_webhook_jobs
memberships_billing
order_type_bundle
profile_stripe_customer
rls_app_policies
rls_policies
seminar_access_wrapper
seminar_attendee_wrapper
seminar_host_guard
seminar_host_helper
seminar_sessions
sessions_and_orders
storage_buckets
sync_livekit_webhook_jobs
teacher_catalog

## Verification Run (ops/verify_all.sh)
- APP_ENV: development (dev)
- Skipped checks: Local DB reset
- Env guard (backend/.env not tracked): PASS
- Env validation: PASS
- Env contract check: PASS
- Stripe test verification: PASS
- Supabase env verification: PASS
- Remote DB verify: FAIL
- Local DB reset: SKIP
- Backend tests: PASS
- Backend smoke: FAIL
- Flutter tests: FAIL
- Landing tests: PASS
- Landing build: PASS

## Remote DB Verify (read-only)
Status: COMPLETED
- App tables: 57
- RLS disabled tables: live_event_registrations
live_events
- Tables without policies: live_event_registrations
live_events
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=false)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: public-media should be public
- Migration tracking: schema_migrations present
- Migrations missing in DB: 001_app_schema.sql
002_teacher_catalog.sql
003_sessions_and_orders.sql
004_memberships_billing.sql
005_course_entitlements.sql
005_livekit_webhook_jobs.sql
006_course_pricing.sql
006_seminar_sessions.sql
007_rls_policies.sql
008_add_next_run_at_to_livekit_webhook_jobs.sql
008_rls_app_policies.sql
010_fix_livekit_job_id.sql
011_seminar_host_helper.sql
012_seminar_access_wrapper.sql
013_seminar_attendee_wrapper.sql
014_seminar_host_guard.sql
015_profile_stripe_customer.sql
016_course_bundles.sql
017_order_type_bundle.sql
018_storage_buckets.sql
202511180129_sync_livekit_webhook_jobs.sql
- Migrations extra in DB: 027_classroom
028_media_library
029_welcome_cards
add_next_run_at_to_livekit_webhook_jobs
app_schema
auth_profile_provider_columns
aveli_pro_platform
course_bundles
course_entitlements
course_entitlements_and_storage_policies
course_pricing
fix_livekit_job_id
fix_purchases_and_claim_tokens
lesson_pricing
live_events
livekit_webhook_jobs
memberships_billing
order_type_bundle
profile_stripe_customer
rls_app_policies
rls_policies
seminar_access_wrapper
seminar_attendee_wrapper
seminar_host_guard
seminar_host_helper
seminar_sessions
sessions_and_orders
storage_buckets
sync_livekit_webhook_jobs
teacher_catalog

## Remote DB Verify (read-only)
Status: COMPLETED
- App tables: 57
- RLS disabled tables: live_event_registrations
live_events
- Tables without policies: live_event_registrations
live_events
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=false)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: public-media should be public
- Migration tracking: schema_migrations present
- Migrations missing in DB: 001_app_schema.sql
002_teacher_catalog.sql
003_sessions_and_orders.sql
004_memberships_billing.sql
005_course_entitlements.sql
005_livekit_webhook_jobs.sql
006_course_pricing.sql
006_seminar_sessions.sql
007_rls_policies.sql
008_add_next_run_at_to_livekit_webhook_jobs.sql
008_rls_app_policies.sql
010_fix_livekit_job_id.sql
011_seminar_host_helper.sql
012_seminar_access_wrapper.sql
013_seminar_attendee_wrapper.sql
014_seminar_host_guard.sql
015_profile_stripe_customer.sql
016_course_bundles.sql
017_order_type_bundle.sql
018_storage_buckets.sql
202511180129_sync_livekit_webhook_jobs.sql
- Migrations extra in DB: 027_classroom
028_media_library
029_welcome_cards
add_next_run_at_to_livekit_webhook_jobs
app_schema
auth_profile_provider_columns
aveli_pro_platform
course_bundles
course_entitlements
course_entitlements_and_storage_policies
course_pricing
fix_livekit_job_id
fix_purchases_and_claim_tokens
lesson_pricing
live_events
livekit_webhook_jobs
memberships_billing
order_type_bundle
profile_stripe_customer
rls_app_policies
rls_policies
seminar_access_wrapper
seminar_attendee_wrapper
seminar_host_guard
seminar_host_helper
seminar_sessions
sessions_and_orders
storage_buckets
sync_livekit_webhook_jobs
teacher_catalog

## Remote DB Verify (read-only)
Status: COMPLETED
- App tables: 57
- RLS disabled tables: live_event_registrations
live_events
- Tables without policies: live_event_registrations
live_events
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=false)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: public-media should be public
- Migration tracking: schema_migrations present
- Migrations missing in DB: 001_app_schema.sql
002_teacher_catalog.sql
003_sessions_and_orders.sql
004_memberships_billing.sql
005_course_entitlements.sql
005_livekit_webhook_jobs.sql
006_course_pricing.sql
006_seminar_sessions.sql
007_rls_policies.sql
008_add_next_run_at_to_livekit_webhook_jobs.sql
008_rls_app_policies.sql
010_fix_livekit_job_id.sql
011_seminar_host_helper.sql
012_seminar_access_wrapper.sql
013_seminar_attendee_wrapper.sql
014_seminar_host_guard.sql
015_profile_stripe_customer.sql
016_course_bundles.sql
017_order_type_bundle.sql
018_storage_buckets.sql
202511180129_sync_livekit_webhook_jobs.sql
- Migrations extra in DB: 027_classroom
028_media_library
029_welcome_cards
add_next_run_at_to_livekit_webhook_jobs
app_schema
auth_profile_provider_columns
aveli_pro_platform
course_bundles
course_entitlements
course_entitlements_and_storage_policies
course_pricing
fix_livekit_job_id
fix_purchases_and_claim_tokens
lesson_pricing
live_events
livekit_webhook_jobs
memberships_billing
order_type_bundle
profile_stripe_customer
rls_app_policies
rls_policies
seminar_access_wrapper
seminar_attendee_wrapper
seminar_host_guard
seminar_host_helper
seminar_sessions
sessions_and_orders
storage_buckets
sync_livekit_webhook_jobs
teacher_catalog

## Verification Run (ops/verify_all.sh)
- APP_ENV: development (dev)
- Skipped checks: Local DB reset,Flutter tests
- Env guard (backend/.env not tracked): PASS
- Env validation: PASS
- Env contract check: PASS
- Stripe test verification: PASS
- Supabase env verification: PASS
- Remote DB verify: FAIL
- Local DB reset: SKIP
- Backend tests: PASS
- Backend smoke: PASS
- Flutter tests: SKIP
- Landing tests: PASS
- Landing build: PASS

## Remote DB Verify (read-only)
Status: COMPLETED
- App tables: 57
- RLS disabled tables: live_event_registrations
live_events
- Tables without policies: live_event_registrations
live_events
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=false)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: public-media should be public
- Migration tracking: schema_migrations present
- Migrations missing in DB: 001_app_schema.sql
002_teacher_catalog.sql
003_sessions_and_orders.sql
004_memberships_billing.sql
005_course_entitlements.sql
005_livekit_webhook_jobs.sql
006_course_pricing.sql
006_seminar_sessions.sql
007_rls_policies.sql
008_add_next_run_at_to_livekit_webhook_jobs.sql
008_rls_app_policies.sql
010_fix_livekit_job_id.sql
011_seminar_host_helper.sql
012_seminar_access_wrapper.sql
013_seminar_attendee_wrapper.sql
014_seminar_host_guard.sql
015_profile_stripe_customer.sql
016_course_bundles.sql
017_order_type_bundle.sql
018_storage_buckets.sql
202511180129_sync_livekit_webhook_jobs.sql
- Migrations extra in DB: 027_classroom
028_media_library
029_welcome_cards
add_next_run_at_to_livekit_webhook_jobs
app_schema
auth_profile_provider_columns
aveli_pro_platform
course_bundles
course_entitlements
course_entitlements_and_storage_policies
course_pricing
fix_livekit_job_id
fix_purchases_and_claim_tokens
lesson_pricing
live_events
livekit_webhook_jobs
memberships_billing
order_type_bundle
profile_stripe_customer
rls_app_policies
rls_policies
seminar_access_wrapper
seminar_attendee_wrapper
seminar_host_guard
seminar_host_helper
seminar_sessions
sessions_and_orders
storage_buckets
sync_livekit_webhook_jobs
teacher_catalog

## Verification Run (ops/verify_all.sh)
- APP_ENV: development (dev)
- Skipped checks: Local DB reset,Flutter tests
- Env guard (backend/.env not tracked): PASS
- Env validation: PASS
- Env contract check: PASS
- Stripe test verification: PASS
- Supabase env verification: PASS
- Remote DB verify: FAIL
- Local DB reset: SKIP
- Backend tests: PASS
- Backend smoke: PASS
- Flutter tests: SKIP
- Landing tests: PASS
- Landing build: PASS
