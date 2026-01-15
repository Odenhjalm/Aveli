-- 010_fix_livekit_job_id.sql
-- Normalize livekit_webhook_jobs columns id/attempt/next_run_at and ensure touch trigger.
-- Replay-safe: skip if table isn't created yet (it may be created by a later timestamp migration).

begin;

-- Guard: if the table does not exist yet, do not fail replay. Just skip.
do $do$
begin
  if to_regclass('app.livekit_webhook_jobs') is null then
    raise notice 'Skipping 010_fix_livekit_job_id.sql: missing table app.livekit_webhook_jobs';
    return;
  end if;

  -- rename job_id -> id if needed
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'app'
      and table_name = 'livekit_webhook_jobs'
      and column_name = 'id'
  ) and exists (
    select 1
    from information_schema.columns
    where table_schema = 'app'
      and table_name = 'livekit_webhook_jobs'
      and column_name = 'job_id'
  ) then
    execute $sql$alter table app.livekit_webhook_jobs rename column job_id to id$sql$;
  end if;

  -- rename attempts -> attempt if needed
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'app'
      and table_name = 'livekit_webhook_jobs'
      and column_name = 'attempt'
  ) and exists (
    select 1
    from information_schema.columns
    where table_schema = 'app'
      and table_name = 'livekit_webhook_jobs'
      and column_name = 'attempts'
  ) then
    execute $sql$alter table app.livekit_webhook_jobs rename column attempts to attempt$sql$;
  end if;

  -- add next_run_at (idempotent)
  execute $sql$
    alter table app.livekit_webhook_jobs
      add column if not exists next_run_at timestamptz not null default now()
  $sql$;

  -- ensure updated_at trigger function exists (idempotent)
  execute $sql$
    create or replace function app.touch_livekit_webhook_jobs()
    returns trigger
    language plpgsql
    as $fn$
    begin
      new.updated_at = now();
      return new;
    end;
    $fn$;
  $sql$;

  -- ensure trigger exists (idempotent)
  execute $sql$
    drop trigger if exists trg_livekit_webhook_jobs_touch on app.livekit_webhook_jobs;
  $sql$;

  execute $sql$
    create trigger trg_livekit_webhook_jobs_touch
    before update on app.livekit_webhook_jobs
    for each row execute procedure app.touch_livekit_webhook_jobs();
  $sql$;

end
$do$;

commit;
