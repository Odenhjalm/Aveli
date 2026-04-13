create table if not exists app.payment_events (
  event_id text not null,
  payload jsonb not null default '{}'::jsonb,
  event_type text generated always as (payload ->> 'type') stored,
  source text not null default 'stripe',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  processed_at timestamptz not null default now(),
  constraint payment_events_pkey primary key (event_id),
  constraint payment_events_source_check check (source = 'stripe'),
  constraint payment_events_event_id_check check (btrim(event_id) <> '')
);

create or replace function app.reject_payment_events_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
begin
  raise exception
    'app.payment_events is append-only webhook idempotency support and is not payment or membership authority';
end;
$$;

drop trigger if exists payment_events_append_only on app.payment_events;

create trigger payment_events_append_only
before update or delete on app.payment_events
for each row
execute function app.reject_payment_events_mutation();

comment on table app.payment_events is
  'Append-only Stripe webhook idempotency support surface only. This table is not purchase, payment settlement, membership, access, pricing, or Stripe runtime authority.';

comment on column app.payment_events.event_id is
  'Stripe webhook event id used only for deterministic duplicate detection.';

comment on column app.payment_events.payload is
  'Raw Stripe event support payload for observability and event type extraction only; not payment or membership truth.';

comment on column app.payment_events.event_type is
  'Derived Stripe event type for support inspection only; not payment or membership truth.';

comment on column app.payment_events.processed_at is
  'Webhook idempotency admission timestamp for the existing insert-on-conflict flow; not proof of payment settlement or membership mutation.';
