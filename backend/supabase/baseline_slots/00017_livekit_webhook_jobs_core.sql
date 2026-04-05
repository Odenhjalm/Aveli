-- Local canonical LiveKit webhook queue required by backend worker boot.
-- Minimal core schema only.
-- next_run_at is intentionally nullable because the current runtime fail path
-- sets it to null when a job reaches terminal failed state.

create table app.livekit_webhook_jobs (
  id uuid primary key default extensions.gen_random_uuid(),
  event text not null,
  payload jsonb not null,
  status text not null default 'pending',
  attempt integer not null default 0,
  last_error text,
  locked_at timestamptz,
  last_attempt_at timestamptz,
  updated_at timestamptz not null default now(),
  next_run_at timestamptz default now()
);
