-- 005_livekit_webhook_jobs.sql
-- Queue for processing LiveKit webhooks asynchronously.

begin;

create table if not exists app.livekit_webhook_jobs (
  job_id uuid primary key default gen_random_uuid(),
  event text not null,
  payload jsonb not null,
  status text not null default 'pending',
  attempts integer not null default 0,
  error text,
  scheduled_at timestamptz not null default now(),
  locked_at timestamptz,
  last_attempted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_livekit_webhook_jobs_status
  on app.livekit_webhook_jobs(status, scheduled_at);

comment on table app.livekit_webhook_jobs is 'Persistent job queue for LiveKit event handling.';

drop trigger if exists trg_livekit_webhook_jobs_touch on app.livekit_webhook_jobs;
create trigger trg_livekit_webhook_jobs_touch
before update on app.livekit_webhook_jobs
for each row execute procedure app.set_updated_at();

commit;
