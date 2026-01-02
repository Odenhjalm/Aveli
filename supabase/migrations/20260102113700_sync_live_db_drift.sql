-- 20260102113700_sync_live_db_drift.sql
-- Baseline sync for live DB-only migrations.
-- sync-migrations: course_entitlements_and_storage_policies, fix_purchases_and_claim_tokens, aveli_pro_platform, lesson_pricing, live_events, auth_profile_provider_columns, 027_classroom, 028_media_library, 029_welcome_cards

begin;

select 1;

do $$
begin
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    insert into supabase_migrations.schema_migrations (version, name)
    values ('20260102113700', 'sync_live_db_drift')
    on conflict (version) do nothing;
  end if;
end $$;

commit;
