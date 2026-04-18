create table app.livekit_webhook_jobs (
  id uuid not null default gen_random_uuid(),
  event_id text,
  event_type text,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'paused',
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint livekit_webhook_jobs_pkey primary key (id),

  constraint livekit_webhook_jobs_status_paused_check
    check (status = 'paused'),

  constraint livekit_webhook_jobs_attempts_zero_check
    check (attempts = 0)
);

comment on table app.livekit_webhook_jobs is
  'Inert LiveKit webhook storage. No processing, retry, or domain mutation is allowed.';

create index livekit_webhook_jobs_event_id_idx
  on app.livekit_webhook_jobs (event_id);

create table app.payment_events (
  event_id text not null,
  source text not null default 'stripe'::text,
  payload jsonb not null default '{}'::jsonb,
  event_type text generated always as ((payload ->> 'type'::text)) stored,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint payment_events_pkey primary key (event_id),

  constraint payment_events_event_id_not_blank_check
    check (btrim(event_id) <> ''),

  constraint payment_events_source_not_blank_check
    check (btrim(source) <> '')
);

create index payment_events_source_idx
  on app.payment_events (source);

create index payment_events_created_at_idx
  on app.payment_events (created_at);

comment on table app.payment_events is
  'Webhook idempotency and immutable observability support only. Processing state must not live in app.payment_events; app.orders, app.payments, and app.memberships remain canonical commerce authority.';

comment on column app.payment_events.event_id is
  'Provider event idempotency key. It is not payment, order, or membership authority.';

comment on column app.payment_events.metadata is
  'Provider/context metadata for observability only. It is not processing state authority.';

create or replace function app.prevent_payment_events_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
begin
  raise exception 'app.payment_events is append-only observability support';
end;
$$;

create trigger payment_events_append_only
before update or delete on app.payment_events
for each row
execute function app.prevent_payment_events_mutation();

create table app.billing_logs (
  id uuid not null default gen_random_uuid(),
  user_id uuid,
  related_order_id uuid,
  step text not null,
  info jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint billing_logs_pkey primary key (id),

  constraint billing_logs_user_id_fkey
    foreign key (user_id)
    references app.auth_subjects (user_id),

  constraint billing_logs_related_order_id_fkey
    foreign key (related_order_id)
    references app.orders (id),

  constraint billing_logs_step_not_blank_check
    check (btrim(step) <> '')
);

create index billing_logs_user_id_idx
  on app.billing_logs (user_id);

create index billing_logs_related_order_id_idx
  on app.billing_logs (related_order_id);

create index billing_logs_step_idx
  on app.billing_logs (step);

comment on table app.billing_logs is
  'Billing observability support only. No authority over orders, payments, memberships, checkout state, or provider settlement.';

comment on column app.billing_logs.step is
  'Deterministic observability step name for operator tracing.';

comment on column app.billing_logs.info is
  'Structured observability payload. It is not commerce domain authority.';

create or replace function app.prevent_billing_logs_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
begin
  raise exception 'app.billing_logs is append-only observability support';
end;
$$;

create trigger billing_logs_append_only
before update or delete on app.billing_logs
for each row
execute function app.prevent_billing_logs_mutation();

create table app.stripe_customers (
  user_id uuid not null,
  customer_id text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint stripe_customers_pkey primary key (user_id),

  constraint stripe_customers_customer_id_key
    unique (customer_id),

  constraint stripe_customers_user_id_fkey
    foreign key (user_id)
    references app.auth_subjects (user_id),

  constraint stripe_customers_customer_id_not_blank_check
    check (btrim(customer_id) <> '')
);

comment on table app.stripe_customers is
  'Stripe customer mapping. Infrastructure-only correlation, not domain authority.';

create table app.media_events (
  id uuid not null default gen_random_uuid(),
  media_asset_id uuid not null,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint media_events_pkey primary key (id),

  constraint media_events_media_asset_id_fkey
    foreign key (media_asset_id)
    references app.media_assets (id)
    on delete cascade,

  constraint media_events_event_type_not_blank_check
    check (btrim(event_type) <> '')
);

create index media_events_media_asset_id_idx
  on app.media_events (media_asset_id);

comment on table app.media_events is
  'Media lifecycle observability log. Does not affect media state or processing authority.';

create table app.auth_events (
  event_id uuid not null default gen_random_uuid(),
  actor_user_id uuid,
  subject_user_id uuid not null,
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint auth_events_pkey primary key (event_id),

  constraint auth_events_actor_user_id_fkey
    foreign key (actor_user_id)
    references app.auth_subjects (user_id)
    on delete set null,

  constraint auth_events_subject_user_id_fkey
    foreign key (subject_user_id)
    references app.auth_subjects (user_id)
    on delete cascade,

  constraint auth_events_event_type_check
    check (
      event_type in (
        'admin_bootstrap_consumed',
        'onboarding_completed',
        'teacher_role_granted',
        'teacher_role_revoked'
      )
    )
);

create index auth_events_actor_user_id_idx
  on app.auth_events (actor_user_id);

create index auth_events_subject_user_id_idx
  on app.auth_events (subject_user_id);

create index auth_events_event_type_idx
  on app.auth_events (event_type);

comment on table app.auth_events is
  'Auth and onboarding observability support. Role and onboarding authority remain app.auth_subjects.';

comment on column app.auth_events.event_type is
  'Closed auth event family for operator traceability only.';
