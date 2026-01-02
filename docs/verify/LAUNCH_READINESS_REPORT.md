# Launch Readiness Report

Status: NOT READY (remote DB verify failing; prod gate blocked)

## Remote DB Verify Policy
- Entrypoint: `backend/scripts/db_verify_remote_readonly.sh`
- Master env (read-only): `/home/oden/Aveli/backend/.env`
- `APP_ENV=development`: non-blocking (reported in launch report)
- `APP_ENV=production`: blocking (verify_all exits non-zero)

## Pass/Fail Matrix
| Area | Status | Notes |
| --- | --- | --- |
| Env guard (backend/.env not tracked) | PASS | guardrails active |
| Env validation | PASS | warnings for missing NEXT_PUBLIC_* envs |
| Env contract check | PASS | dev mode |
| Stripe test verification | PASS | active keys aligned to test |
| Supabase env verification | PASS | storage list + read-only DB check |
| Remote DB read-only verify | FAIL | non-blocking in dev; see latest run |
| RLS enabled for app tables | FAIL | remote DB verify flagged live_event* |
| RLS policies present | FAIL | remote DB verify flagged missing policies |
| Storage buckets + policies | FAIL | public-media should be public |
| Backend tests | PASS | 70 passed, 3 skipped |
| Backend smoke (Stripe checkout + membership) | PASS | subscriptions disabled |
| Flutter tests | PASS | unit/widget tests OK |
| Flutter integration tests | SKIP | FLUTTER_DEVICE not set |
| Landing tests | PASS | vitest ok |
| Landing build | PASS | Next.js build ok |

## Fixes Applied
- Added remote DB verify entrypoint (read-only) with `/tmp` JSON log output and master env sourcing.
- Added env contract + Stripe/Supabase verifiers with APP_ENV-aware checks and new sb_* key support.
- Updated backend env templates (new key names, dev/prod guidance, CORS list formatting).
- Added psycopg-pool and `@sentry/nextjs`; verify_all now runs via Poetry/NPM end-to-end.
- QA teacher smoke now skips subscription flow when `SUBSCRIPTIONS_ENABLED=false`.

## Remaining Blockers
- Remote DB verify failures (RLS disabled tables, missing policies, storage bucket visibility, migrations drift).

## Verification Runs
- APP_ENV=development `./verify_all.sh`: PASS (remote DB verify failed but non-blocking; Flutter integration skipped)

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

## Remote DB Verify (read-only)
Status: FAILED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
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
Status: FAILED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
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
Status: FAILED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
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
Status: FAILED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
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
- Mode: development
- Remote DB master env: /home/oden/Aveli/backend/.env
- Env guard (backend/.env not tracked): PASS
- Env validation: PASS
- Poetry install: PASS
- Env contract check: PASS
- Stripe test/live verification: PASS
- Supabase env verification: PASS
- Remote DB verify (read-only, non-blocking): FAIL (non-blocking)
- Local DB reset: SKIP
- Backend tests: PASS
- Backend smoke: PASS
- Flutter tests: PASS
- Flutter integration tests: SKIP (FLUTTER_DEVICE not set)
- Landing deps: PASS
- Landing tests: PASS
- Landing build: PASS
