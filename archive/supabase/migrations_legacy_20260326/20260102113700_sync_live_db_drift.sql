-- 20260102113700_sync_live_db_drift.sql
-- Baseline sync for live DB-only migrations.
-- sync-migrations: course_entitlements_and_storage_policies, fix_purchases_and_claim_tokens, aveli_pro_platform, lesson_pricing, live_events, auth_profile_provider_columns, 027_classroom, 028_media_library, 029_welcome_cards

begin;

select 1;

commit;
