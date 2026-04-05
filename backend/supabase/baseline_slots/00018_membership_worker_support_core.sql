-- Local canonical membership worker support required by backend worker startup.
-- Minimal core schema only.
-- This slot intentionally excludes remote billing and membership parity fields,
-- RLS, policies, grants, checks, and extra indexes.

create table app.memberships (
  membership_id uuid not null default extensions.gen_random_uuid(),
  user_id uuid not null,
  status text not null default 'active',
  end_date timestamptz,
  constraint memberships_pkey primary key (membership_id)
);

create table app.billing_logs (
  id uuid not null default extensions.gen_random_uuid(),
  user_id uuid,
  step text,
  info jsonb,
  created_at timestamptz default now(),
  constraint billing_logs_pkey primary key (id)
);
