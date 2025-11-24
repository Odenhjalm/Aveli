-- 202511180129_sync_livekit_webhook_jobs.sql
-- Synchronize livekit_webhook_jobs schema with backend expectations.

begin;

do $$
begin
  -- Rename job_id -> id
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'id'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'job_id'
  ) then
    execute 'alter table app.livekit_webhook_jobs rename column job_id to id';
  end if;

  -- Rename attempts -> attempt
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'attempt'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'attempts'
  ) then
    execute 'alter table app.livekit_webhook_jobs rename column attempts to attempt';
  end if;

  -- Ensure attempt column has a default (0) and is not null.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'attempt'
  ) then
    execute 'alter table app.livekit_webhook_jobs alter column attempt set default 0';
    execute 'alter table app.livekit_webhook_jobs alter column attempt set not null';
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
      execute 'alter table app.livekit_webhook_jobs rename column error to last_error';
    else
      execute 'alter table app.livekit_webhook_jobs add column last_error text';
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
      execute 'alter table app.livekit_webhook_jobs rename column last_attempted_at to last_attempt_at';
    else
      execute 'alter table app.livekit_webhook_jobs add column last_attempt_at timestamptz';
    end if;
  end if;

  -- Add next_run_at if missing
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'livekit_webhook_jobs' and column_name = 'next_run_at'
  ) then
    execute 'alter table app.livekit_webhook_jobs add column next_run_at timestamptz not null default now()';
  end if;
end$$;

-- Ensure updated_at trigger exists and points to app.set_updated_at
drop trigger if exists trg_livekit_webhook_jobs_touch on app.livekit_webhook_jobs;
create trigger trg_livekit_webhook_jobs_touch
before update on app.livekit_webhook_jobs
for each row execute procedure app.set_updated_at();

commit;
