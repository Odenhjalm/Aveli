# Launch Readiness Report

Status: READY (dev gates pass; remote DB verify PASS)

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
| Remote DB read-only verify | PASS | PASS in dev; blocking in prod |
| RLS enabled for app tables | PASS | live_event* RLS restored |
| RLS policies present | PASS | live_event* policies added |
| Storage buckets + policies | PASS | public-media set to public |
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
- Enabled live events RLS + policies (`20260102113500_live_events_rls.sql`).
- Aligned storage bucket visibility (`20260102113600_storage_public_media.sql`).
- Added sync migration markers + drift normalization (`20260102113700_sync_live_db_drift.sql`, `backend/scripts/db_verify_remote_readonly.sh`).

## Remaining Blockers
- None for development verification (prod still requires live Stripe keys and blocking remote DB verify).

## Verification Runs
- APP_ENV=development `./verify_all.sh`: PASS (remote DB verify PASS; Flutter integration skipped)

## Next 5 Actions
1. Run `APP_ENV=production ./verify_all.sh` with live Stripe keys available.
2. Confirm remote DB verify blocks correctly in production mode.
3. Set `NEXT_PUBLIC_*` landing env vars to clear validation warnings.
4. Run Flutter integration tests with `FLUTTER_DEVICE=linux`.
5. Review `npm audit` warnings for the landing build pipeline.

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
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: 001_app_schema
002_teacher_catalog
003_sessions_and_orders
004_memberships_billing
005_course_entitlements
005_livekit_webhook_jobs
006_course_pricing
006_seminar_sessions
007_rls_policies
008_add_next_run_at_to_livekit_webhook_jobs
008_rls_app_policies
010_fix_livekit_job_id
011_seminar_host_helper
012_seminar_access_wrapper
013_seminar_attendee_wrapper
014_seminar_host_guard
015_profile_stripe_customer
016_course_bundles
017_order_type_bundle
018_storage_buckets
027_cla
029_welcome_card
202511180129_sync_livekit_webhook_jobs
20260102113500_live_events_rls
20260102113600_storage_public_media
20260102113700_sync_live_db_drift
_and_
_and_claim_token
auth_profile_provider_column
cour
e
e_entitlement
fix_purcha
le
live_event
on_pricing
room
torage_policie
- Migrations extra in DB: 027_classroom
029_welcome_cards
add_next_run_at_to_livekit_webhook_jobs
app_schema
auth_profile_provider_columns
course_bundles
course_entitlements
course_entitlements_and_storage_policies
course_pricing
fix_livekit_job_id
fix_purchases_and_claim_tokens
lesson_pricing
live_events
live_events_rls
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
storage_public_media
sync_live_db_drift
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

## Remote DB Verify (read-only)
Status: COMPLETED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 57
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: none
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: COMPLETED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 57
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: none
- Migrations extra in DB: none

## Verification Run (ops/verify_all.sh)
- Mode: development
- Remote DB master env: /home/oden/Aveli/backend/.env
- Env guard (backend/.env not tracked): PASS
- Env validation: PASS
- Poetry install: PASS
- Env contract check: PASS
- Stripe test/live verification: PASS
- Supabase env verification: PASS
- Remote DB verify (read-only, non-blocking): PASS
- Local DB reset: SKIP
- Backend tests: PASS
- Backend smoke: PASS
- Flutter tests: PASS
- Flutter integration tests: SKIP (FLUTTER_DEVICE not set)
- Landing deps: PASS
- Landing tests: PASS
- Landing build: PASS

## Remote DB Verify (read-only)
Status: FAILED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: 027_classroom
028_media_library
029_welcome_cards
auth_profile_provider_columns
aveli_pro_platform
course_entitlements_and_storage_policies
fix_purchases_and_claim_tokens
lesson_pricing
live_events
order_type_bundle
rls_policies
storage_buckets
- Migrations extra in DB: add_next_run_at_to_livekit_webhook_jobs
add_next_run_at_to_livekit_webhook_jobs
course_pricing
remote_schema

## Remote DB Verify (read-only)
Status: FAILED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: 027_classroom
028_media_library
029_welcome_cards
auth_profile_provider_columns
aveli_pro_platform
course_entitlements_and_storage_policies
fix_purchases_and_claim_tokens
lesson_pricing
live_events
order_type_bundle
rls_policies
storage_buckets
- Migrations extra in DB: add_next_run_at_to_livekit_webhook_jobs
add_next_run_at_to_livekit_webhook_jobs
course_pricing
remote_schema

## Remote DB Verify (read-only)
Status: FAILED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: 027_classroom
028_media_library
029_welcome_cards
auth_profile_provider_columns
aveli_pro_platform
course_entitlements_and_storage_policies
fix_purchases_and_claim_tokens
lesson_pricing
live_events
order_type_bundle
rls_policies
storage_buckets
- Migrations extra in DB: add_next_run_at_to_livekit_webhook_jobs
add_next_run_at_to_livekit_webhook_jobs
course_pricing
remote_schema

## Remote DB Verify (read-only)
Status: FAILED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: 027_classroom
028_media_library
029_welcome_cards
auth_profile_provider_columns
aveli_pro_platform
course_entitlements_and_storage_policies
fix_purchases_and_claim_tokens
lesson_pricing
live_events
order_type_bundle
rls_policies
storage_buckets
- Migrations extra in DB: add_next_run_at_to_livekit_webhook_jobs
add_next_run_at_to_livekit_webhook_jobs
course_pricing
remote_schema

## Remote DB Verify (read-only)
Status: FAILED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: 027_classroom
028_media_library
029_welcome_cards
auth_profile_provider_columns
aveli_pro_platform
course_entitlements_and_storage_policies
fix_purchases_and_claim_tokens
lesson_pricing
live_events
order_type_bundle
rls_policies
storage_buckets
- Migrations extra in DB: add_next_run_at_to_livekit_webhook_jobs
add_next_run_at_to_livekit_webhook_jobs
course_pricing
remote_schema

## Remote DB Verify (read-only)
Status: COMPLETED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: none
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: COMPLETED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: none
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: COMPLETED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: none
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: COMPLETED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: none
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: FAILED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: postgrest_seminar_rpc
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: FAILED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: postgrest_seminar_rpc
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: FAILED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: postgrest_seminar_rpc
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: COMPLETED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: none
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: COMPLETED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: none
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: COMPLETED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: none
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: COMPLETED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: none
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: COMPLETED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: none
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: COMPLETED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: none
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: COMPLETED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: none
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: COMPLETED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: none
- Migrations extra in DB: none

## Remote DB Verify (read-only)
Status: COMPLETED
- Master env: /home/oden/Aveli/backend/.env
- SUPABASE_DB_URL: set
- App tables: 58
- RLS disabled tables: none
- Tables without policies: none
- Storage buckets: audio_private (public=false)
brand (public=false)
course-media (public=false)
lesson-media (public=false)
public-media (public=true)
welcome-cards (public=false)
- Storage objects RLS: t
- Storage policies: storage_owner_private_rw [ALL]
storage_public_read_avatars_thumbnails [SELECT]
storage_service_role_full_access [ALL]
storage_signed_private_read [SELECT]
- Storage bucket sanity: ok
- Migration tracking: schema_migrations present
- Migrations missing in DB: none
- Migrations extra in DB: none

## Verification Run (ops/verify_all.sh)
- APP_ENV: development (dev)
- Stripe mode: live
- Backend env file: /home/oden/Aveli/backend/.env
- Backend env overlay: none
- Env guard: PASS
- Env validation: PASS
- Poetry install: PASS
- Env contract: PASS
- Stripe verify: PASS
- Supabase verify: PASS
- Remote DB verify: PASS
- Backend tests: PASS
- Backend smoke: PASS
- Flutter unit tests: PASS
- Flutter integration tests: PASS
- Landing deps: PASS
- Landing tests: PASS
- Landing build: PASS
