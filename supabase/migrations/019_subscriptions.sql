-- 019_subscriptions.sql
-- Add Stripe subscription mirror table.

begin;

create table if not exists app.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  subscription_id text not null,
  status text not null,
  customer_id text,
  price_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (subscription_id)
);

create index if not exists idx_subscriptions_user on app.subscriptions(user_id);

alter table app.subscriptions enable row level security;

drop policy if exists subscriptions_service_role on app.subscriptions;
create policy subscriptions_service_role on app.subscriptions
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

commit;
