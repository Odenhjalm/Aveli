-- 010_fix_livekit_job_id.sql
-- Normalize livekit_webhook_jobs columns id/attempt/next_run_at and ensure touch trigger.

begin;

-- rename job_id -> id if needed
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'app' AND table_name = 'livekit_webhook_jobs' AND column_name = 'id'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'app' AND table_name = 'livekit_webhook_jobs' AND column_name = 'job_id'
  ) THEN
    EXECUTE 'alter table app.livekit_webhook_jobs rename column job_id to id';
  END IF;
END$$;

-- rename attempts -> attempt if needed
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'app' AND table_name = 'livekit_webhook_jobs' AND column_name = 'attempt'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'app' AND table_name = 'livekit_webhook_jobs' AND column_name = 'attempts'
  ) THEN
    EXECUTE 'alter table app.livekit_webhook_jobs rename column attempts to attempt';
  END IF;
END$$;

-- add next_run_at
alter table app.livekit_webhook_jobs
  add column if not exists next_run_at timestamptz not null default now();

-- ensure updated_at trigger exists
create or replace function app.touch_livekit_webhook_jobs()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_livekit_webhook_jobs_touch on app.livekit_webhook_jobs;
create trigger trg_livekit_webhook_jobs_touch
before update on app.livekit_webhook_jobs
for each row execute procedure app.touch_livekit_webhook_jobs();

commit;
