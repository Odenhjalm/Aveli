-- Phase 1: additive shadow-mode ledger for deterministic Stripe idempotency.

begin;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'payment_command_type'
      and n.nspname = 'app'
  ) then
    create type app.payment_command_type as enum (
      'course_purchase',
      'bundle_purchase',
      'service_purchase',
      'membership_start',
      'membership_cancel'
    );
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'payment_command_status'
      and n.nspname = 'app'
  ) then
    create type app.payment_command_status as enum (
      'created',
      'session_created',
      'waiting_for_webhook',
      'completed',
      'failed'
    );
  end if;
end$$;

create table if not exists app.payment_commands (
  command_id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  command_type app.payment_command_type not null,
  idempotency_key text,
  request_fingerprint text not null,
  request_metadata jsonb not null default '{}'::jsonb,
  status app.payment_command_status not null default 'created',
  stripe_checkout_session_id text,
  stripe_payment_intent_id text,
  stripe_subscription_id text,
  amount_cents integer not null,
  currency text not null,
  course_id uuid,
  bundle_id uuid,
  service_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_payment_commands_user_id
  on app.payment_commands(user_id);

create index if not exists idx_payment_commands_checkout_session_id
  on app.payment_commands(stripe_checkout_session_id);

create index if not exists idx_payment_commands_payment_intent_id
  on app.payment_commands(stripe_payment_intent_id);

create index if not exists idx_payment_commands_subscription_id
  on app.payment_commands(stripe_subscription_id);

do $$
begin
  if to_regprocedure('app.set_updated_at()') is not null then
    drop trigger if exists trg_payment_commands_touch on app.payment_commands;
    create trigger trg_payment_commands_touch
      before update on app.payment_commands
      for each row execute function app.set_updated_at();
  end if;
end$$;

create table if not exists app.stripe_event_ledger (
  provider text not null default 'stripe' check (provider = 'stripe'),
  event_id text not null unique,
  event_type text not null,
  received_at timestamptz not null default now(),
  status text not null default 'received' check (status = 'received'),
  raw_event jsonb not null,
  resolved_command_id uuid
);

create index if not exists idx_stripe_event_ledger_received_at
  on app.stripe_event_ledger(received_at desc);

create index if not exists idx_stripe_event_ledger_resolved_command_id
  on app.stripe_event_ledger(resolved_command_id);

commit;
