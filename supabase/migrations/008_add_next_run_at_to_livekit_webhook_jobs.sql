-- 008_add_next_run_at_to_livekit_webhook_jobs.sql
-- Add next_run_at column used for scheduling LiveKit webhook retries.

begin;

alter table if exists app.livekit_webhook_jobs
  add column if not exists next_run_at timestamptz not null default now();

commit;
