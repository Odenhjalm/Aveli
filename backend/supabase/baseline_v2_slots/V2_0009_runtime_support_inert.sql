

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
  id uuid not null default gen_random_uuid(),

  provider text not null,
  provider_event_id text not null,

  payload jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  constraint payment_events_pkey primary key (id),

  constraint payment_events_provider_event_key
    unique (provider, provider_event_id),

  constraint payment_events_provider_not_blank_check
    check (btrim(provider) <> ''),

  constraint payment_events_event_id_not_blank_check
    check (btrim(provider_event_id) <> '')
);

comment on table app.payment_events is
  'Webhook idempotency and observability store. Not a source of payment or membership authority.';



create table app.billing_logs (
  id uuid not null default gen_random_uuid(),

  subject_user_id uuid,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  constraint billing_logs_pkey primary key (id),

  constraint billing_logs_event_type_not_blank_check
    check (btrim(event_type) <> '')
);

comment on table app.billing_logs is
  'Billing observability log. No authority over orders, payments, or memberships.';



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
  id uuid not null default gen_random_uuid(),

  subject_user_id uuid not null,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  constraint auth_events_pkey primary key (id),

  constraint auth_events_subject_user_id_fkey
    foreign key (subject_user_id)
    references app.auth_subjects (user_id),

  constraint auth_events_event_type_not_blank_check
    check (btrim(event_type) <> '')
);

create index auth_events_subject_user_id_idx
  on app.auth_events (subject_user_id);

comment on table app.auth_events is
  'Auth and onboarding observability log. No authority over roles or onboarding state.';