create table app.livekit_webhook_jobs (
  id uuid not null default gen_random_uuid(),
  event text not null,
  payload jsonb not null,
  status text not null default 'pending',
  attempt integer not null default 0,
  next_run_at timestamptz not null default now(),
  locked_at timestamptz,
  last_attempt_at timestamptz,
  last_error text,
  updated_at timestamptz not null default now(),
  constraint livekit_webhook_jobs_pkey primary key (id),
  constraint livekit_webhook_jobs_status_check
    check (status in ('pending', 'processing', 'failed')),
  constraint livekit_webhook_jobs_attempt_check
    check (attempt >= 0)
);

create index idx_livekit_webhook_jobs_due
  on app.livekit_webhook_jobs (status, next_run_at);
