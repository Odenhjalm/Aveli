#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SUPABASE_DB_URL:-}" ]]; then
  echo "SUPABASE_DB_URL is required" >&2
  exit 1
fi

if [[ "${CONFIRM_SCHEMA_MIGRATIONS_FIX:-}" != "1" ]]; then
  echo "Set CONFIRM_SCHEMA_MIGRATIONS_FIX=1 to update supabase_migrations.schema_migrations." >&2
  exit 1
fi

psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 <<'SQL'
begin;

-- Remove entries that are not part of repo migrations.
delete from supabase_migrations.schema_migrations
where name = 'remote_schema';

-- Deduplicate entries to match repo (keep the canonical version).
delete from supabase_migrations.schema_migrations
where name = 'add_next_run_at_to_livekit_webhook_jobs'
  and version in ('008', '010');

delete from supabase_migrations.schema_migrations
where name = 'course_pricing'
  and version = '007';

-- Insert missing migration markers (idempotent).
insert into supabase_migrations.schema_migrations (version, name)
select '20260102113701', '027_classroom'
where not exists (select 1 from supabase_migrations.schema_migrations where name = '027_classroom');

insert into supabase_migrations.schema_migrations (version, name)
select '20260102113702', '028_media_library'
where not exists (select 1 from supabase_migrations.schema_migrations where name = '028_media_library');

insert into supabase_migrations.schema_migrations (version, name)
select '20260102113703', '029_welcome_cards'
where not exists (select 1 from supabase_migrations.schema_migrations where name = '029_welcome_cards');

insert into supabase_migrations.schema_migrations (version, name)
select '20260102113704', 'auth_profile_provider_columns'
where not exists (select 1 from supabase_migrations.schema_migrations where name = 'auth_profile_provider_columns');

insert into supabase_migrations.schema_migrations (version, name)
select '20260102113705', 'aveli_pro_platform'
where not exists (select 1 from supabase_migrations.schema_migrations where name = 'aveli_pro_platform');

insert into supabase_migrations.schema_migrations (version, name)
select '20260102113706', 'course_entitlements_and_storage_policies'
where not exists (select 1 from supabase_migrations.schema_migrations where name = 'course_entitlements_and_storage_policies');

insert into supabase_migrations.schema_migrations (version, name)
select '20260102113707', 'fix_purchases_and_claim_tokens'
where not exists (select 1 from supabase_migrations.schema_migrations where name = 'fix_purchases_and_claim_tokens');

insert into supabase_migrations.schema_migrations (version, name)
select '20260102113708', 'lesson_pricing'
where not exists (select 1 from supabase_migrations.schema_migrations where name = 'lesson_pricing');

insert into supabase_migrations.schema_migrations (version, name)
select '20260102113709', 'live_events'
where not exists (select 1 from supabase_migrations.schema_migrations where name = 'live_events');

insert into supabase_migrations.schema_migrations (version, name)
select '20260102113710', 'order_type_bundle'
where not exists (select 1 from supabase_migrations.schema_migrations where name = 'order_type_bundle');

insert into supabase_migrations.schema_migrations (version, name)
select '20260102113711', 'rls_policies'
where not exists (select 1 from supabase_migrations.schema_migrations where name = 'rls_policies');

insert into supabase_migrations.schema_migrations (version, name)
select '20260102113712', 'storage_buckets'
where not exists (select 1 from supabase_migrations.schema_migrations where name = 'storage_buckets');

commit;
SQL
