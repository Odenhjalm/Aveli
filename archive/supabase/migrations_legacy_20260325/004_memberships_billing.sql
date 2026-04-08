-- 004_memberships_billing.sql
-- Membership + billing support tables with minimal RLS.

begin;

create table if not exists app.memberships (
    membership_id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    plan_interval text not null check (plan_interval in ('month','year')),
    price_id text not null,
    stripe_customer_id text,
    stripe_subscription_id text,
    start_date timestamptz not null default now(),
    end_date timestamptz,
    status text not null default 'active',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (user_id)
);

comment on table app.memberships is 'Stripe billing memberships for subscription access';

create table if not exists app.payment_events (
    id uuid primary key default gen_random_uuid(),
    event_id text unique not null,
    payload jsonb not null,
    processed_at timestamptz default now()
);

create table if not exists app.billing_logs (
    id uuid primary key default gen_random_uuid(),
    user_id uuid,
    step text,
    info jsonb,
    created_at timestamptz default now()
);

commit;
