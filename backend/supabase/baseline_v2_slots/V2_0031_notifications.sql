create table app.notifications (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  type text not null,
  payload_json jsonb not null,
  dedup_key text not null,
  created_at timestamptz not null default now(),

  constraint notifications_pkey primary key (id),

  constraint notifications_user_id_fkey
    foreign key (user_id)
    references app.auth_subjects (user_id),

  constraint notifications_dedup_key_key
    unique (dedup_key),

  constraint notifications_type_not_blank_check
    check (btrim(type) <> ''),

  constraint notifications_dedup_key_not_blank_check
    check (btrim(dedup_key) <> '')
);

create index notifications_user_id_created_at_idx
  on app.notifications (user_id, created_at desc);

comment on table app.notifications is
  'Canonical notification records. A notification row must exist before any delivery attempt.';

comment on column app.notifications.dedup_key is
  'Domain-provided idempotency key. The database uniqueness constraint is the canonical deduplication boundary.';

create table app.notification_deliveries (
  id uuid not null default gen_random_uuid(),
  notification_id uuid not null,
  channel text not null,
  status text not null default 'pending',
  attempts integer not null default 0,
  last_attempt_at timestamptz,
  error_text text,

  constraint notification_deliveries_pkey primary key (id),

  constraint notification_deliveries_notification_id_fkey
    foreign key (notification_id)
    references app.notifications (id),

  constraint notification_deliveries_notification_channel_key
    unique (notification_id, channel),

  constraint notification_deliveries_channel_check
    check (channel in ('push', 'in_app', 'email')),

  constraint notification_deliveries_status_check
    check (status in ('pending', 'sent', 'failed')),

  constraint notification_deliveries_attempts_check
    check (attempts >= 0)
);

create index notification_deliveries_pending_idx
  on app.notification_deliveries (status, attempts, id)
  where status = 'pending';

comment on table app.notification_deliveries is
  'Notification delivery queue. Delivery workers own status, attempts, and error state.';

create table app.user_devices (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  push_token text not null,
  platform text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),

  constraint user_devices_pkey primary key (id),

  constraint user_devices_user_id_fkey
    foreign key (user_id)
    references app.auth_subjects (user_id),

  constraint user_devices_push_token_key
    unique (push_token),

  constraint user_devices_push_token_not_blank_check
    check (btrim(push_token) <> ''),

  constraint user_devices_platform_not_blank_check
    check (btrim(platform) <> '')
);

create index user_devices_user_id_active_idx
  on app.user_devices (user_id, active);

comment on table app.user_devices is
  'Push delivery routing substrate. Device registration is activated by a later vertical slice.';
