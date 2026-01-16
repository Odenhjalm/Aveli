-- 20260115_230010_live_events_patch_columns.sql
-- Patch remote drift: ensure app.live_events has starts_at/ends_at and the starts_at index.
-- Idempotent: safe if columns already exist.

begin;

-- Add missing columns if needed
alter table app.live_events
  add column if not exists starts_at timestamptz;

alter table app.live_events
  add column if not exists ends_at timestamptz;

-- Create the index only if the column exists (replay-safe)
do $do$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'app'
      and table_name = 'live_events'
      and column_name = 'starts_at'
  ) then
    execute 'create index if not exists idx_live_events_starts_at on app.live_events(starts_at)';
  else
    raise notice 'Skipping idx_live_events_starts_at: app.live_events.starts_at missing';
  end if;
end
$do$;

commit;
