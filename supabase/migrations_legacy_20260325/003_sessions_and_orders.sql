-- 003_sessions_and_orders.sql
-- Adds teacher Connect metadata, sessions, and order extensions for bookings/subscriptions.

begin;

-- Enums -------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'session_visibility'
      and n.nspname = 'app'
  ) then
    create type app.session_visibility as enum ('draft', 'published');
  end if;
end$$;

do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'order_type'
      and n.nspname = 'app'
  ) then
    create type app.order_type as enum ('one_off', 'subscription');
  end if;
end$$;

-- Teachers payout metadata -------------------------------------------------
create table if not exists app.teachers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references app.profiles(user_id) on delete cascade unique,
  stripe_connect_account_id text unique,
  payout_split_pct integer not null default 100 check (payout_split_pct between 0 and 100),
  onboarded_at timestamptz,
  charges_enabled boolean not null default false,
  payouts_enabled boolean not null default false,
  requirements_due jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_teachers_connect_account on app.teachers(stripe_connect_account_id);
comment on table app.teachers is 'Stripe Connect metadata per teacher profile.';

drop trigger if exists trg_teachers_touch on app.teachers;
create trigger trg_teachers_touch
before update on app.teachers
for each row execute procedure app.set_updated_at();

-- Sessions -----------------------------------------------------------------
create table if not exists app.sessions (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references app.profiles(user_id) on delete cascade,
  title text not null,
  description text,
  start_at timestamptz,
  end_at timestamptz,
  capacity integer check (capacity is null or capacity >= 0),
  price_cents integer not null default 0,
  currency text not null default 'sek',
  visibility app.session_visibility not null default 'draft',
  recording_url text,
  stripe_price_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_sessions_teacher on app.sessions(teacher_id);
create index if not exists idx_sessions_visibility on app.sessions(visibility);
create index if not exists idx_sessions_start_at on app.sessions(start_at);
comment on table app.sessions is 'Published sessions created by teachers, surfaced in booking flows.';

drop trigger if exists trg_sessions_touch on app.sessions;
create trigger trg_sessions_touch
before update on app.sessions
for each row execute procedure app.set_updated_at();

create table if not exists app.session_slots (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references app.sessions(id) on delete cascade,
  start_at timestamptz not null,
  end_at timestamptz not null,
  seats_total integer not null default 1 check (seats_total >= 0),
  seats_taken integer not null default 0 check (seats_taken >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(session_id, start_at)
);

create index if not exists idx_session_slots_session on app.session_slots(session_id);
create index if not exists idx_session_slots_time on app.session_slots(start_at, end_at);
comment on table app.session_slots is 'Individual slots for teacher sessions with capacity tracking.';

drop trigger if exists trg_session_slots_touch on app.session_slots;
create trigger trg_session_slots_touch
before update on app.session_slots
for each row execute procedure app.set_updated_at();

-- Order extensions ---------------------------------------------------------
alter table app.orders
  add column if not exists order_type app.order_type not null default 'one_off',
  add column if not exists session_id uuid references app.sessions(id) on delete set null,
  add column if not exists session_slot_id uuid references app.session_slots(id) on delete set null,
  add column if not exists stripe_subscription_id text,
  add column if not exists connected_account_id text,
  add column if not exists stripe_customer_id text;

create index if not exists idx_orders_session on app.orders(session_id);
create index if not exists idx_orders_session_slot on app.orders(session_slot_id);
create index if not exists idx_orders_connected_account on app.orders(connected_account_id);

comment on column app.orders.order_type is 'Differentiate one-off vs subscription orders.';
comment on column app.orders.session_id is 'Parent session (teacher program) reference.';
comment on column app.orders.session_slot_id is 'Specific slot booking reference.';
comment on column app.orders.stripe_subscription_id is 'Stripe subscription ID for billing.';
comment on column app.orders.connected_account_id is 'Stripe Connect destination account.';
comment on column app.orders.stripe_customer_id is 'Stripe Customer associated with the buyer.';

commit;
