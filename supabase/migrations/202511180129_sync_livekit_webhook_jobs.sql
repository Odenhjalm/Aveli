-- 202511180129_sync_livekit_webhook_jobs.sql
-- Sync/normalize livekit_webhook_jobs schema drift for live DB.
-- Replay-safe: skip when app.livekit_webhook_jobs does not exist yet.

begin;

-- Use distinct dollar-quote tags to avoid nested parsing collisions.
do $do$
begin
  if to_regclass('app.livekit_webhook_jobs') is null then
    raise notice 'Skipping 202511180129_sync_livekit_webhook_jobs.sql: missing table app.livekit_webhook_jobs';
    return;
  end if;

  -- Rename job_id -> id
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'id'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'job_id'
  ) then
    execute $sql$alter table app.livekit_webhook_jobs rename column job_id to id$sql$;
  end if;

  -- Rename attempts -> attempt
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'attempt'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'attempts'
  ) then
    execute $sql$alter table app.livekit_webhook_jobs rename column attempts to attempt$sql$;
  end if;

  -- Ensure attempt column has a default (0) and is not null
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'attempt'
  ) then
    execute $sql$alter table app.livekit_webhook_jobs alter column attempt set default 0$sql$;
    execute $sql$alter table app.livekit_webhook_jobs alter column attempt set not null$sql$;
  end if;

  -- Rename error -> last_error or add last_error if neither exists
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'last_error'
  ) then
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'error'
    ) then
      execute $sql$alter table app.livekit_webhook_jobs rename column error to last_error$sql$;
    else
      execute $sql$alter table app.livekit_webhook_jobs add column last_error text$sql$;
    end if;
  end if;

  -- Rename last_attempted_at -> last_attempt_at or add last_attempt_at if missing
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'last_attempt_at'
  ) then
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'last_attempted_at'
    ) then
      execute $sql$alter table app.livekit_webhook_jobs rename column last_attempted_at to last_attempt_at$sql$;
    else
      execute $sql$alter table app.livekit_webhook_jobs add column last_attempt_at timestamptz$sql$;
    end if;
  end if;

  -- Add next_run_at if missing
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'next_run_at'
  ) then
    execute $sql$alter table app.livekit_webhook_jobs add column next_run_at timestamptz not null default now()$sql$;
  end if;
end
$do$;

commit;
