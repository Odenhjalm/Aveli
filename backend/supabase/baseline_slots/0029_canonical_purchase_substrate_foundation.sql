do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n
      on n.oid = t.typnamespace
    where n.nspname = 'app'
      and t.typname = 'order_status'
  ) then
    create type app.order_status as enum (
      'pending',
      'requires_action',
      'processing',
      'paid',
      'canceled',
      'failed',
      'refunded'
    );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n
      on n.oid = t.typnamespace
    where n.nspname = 'app'
      and t.typname = 'order_type'
  ) then
    create type app.order_type as enum (
      'one_off',
      'subscription',
      'bundle'
    );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n
      on n.oid = t.typnamespace
    where n.nspname = 'app'
      and t.typname = 'payment_status'
  ) then
    create type app.payment_status as enum (
      'pending',
      'processing',
      'paid',
      'failed',
      'refunded'
    );
  end if;
end
$$;

create table if not exists app.orders (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  service_id uuid,
  course_id uuid,
  session_id uuid,
  session_slot_id uuid,
  order_type app.order_type not null default 'one_off'::app.order_type,
  amount_cents integer not null,
  currency text not null default 'sek'::text,
  status app.order_status not null default 'pending'::app.order_status,
  stripe_checkout_id text,
  stripe_payment_intent text,
  stripe_subscription_id text,
  stripe_customer_id text,
  connected_account_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint orders_pkey primary key (id),
  constraint orders_course_id_fkey
    foreign key (course_id) references app.courses (id)
);

create table if not exists app.payments (
  id uuid not null default gen_random_uuid(),
  order_id uuid not null,
  provider text not null,
  provider_reference text,
  status app.payment_status not null default 'pending'::app.payment_status,
  amount_cents integer not null,
  currency text not null default 'sek'::text,
  metadata jsonb not null default '{}'::jsonb,
  raw_payload jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payments_pkey primary key (id),
  constraint payments_order_id_fkey
    foreign key (order_id) references app.orders (id) on delete cascade
);

create table if not exists app.stripe_customers (
  user_id uuid not null,
  customer_id text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stripe_customers_pkey primary key (user_id)
);

comment on table app.orders is
  'Canonical purchase identity and lifecycle substrate for order-backed commerce flows.';

comment on table app.payments is
  'Canonical payment settlement substrate tied to app.orders.';

comment on table app.stripe_customers is
  'Retained Stripe customer support substrate only. This table is not purchase, pricing, ownership, or sellability authority.';
