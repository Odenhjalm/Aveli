create table app.notification_push_device_deliveries (
  id uuid not null default gen_random_uuid(),
  delivery_id uuid not null,
  notification_id uuid not null,
  device_id uuid not null,
  status text not null default 'pending',
  attempts integer not null default 0,
  provider_message_id text,
  last_attempt_at timestamptz,
  error_text text,
  created_at timestamptz not null default now(),

  constraint notification_push_device_deliveries_pkey primary key (id),

  constraint notification_push_device_deliveries_delivery_id_fkey
    foreign key (delivery_id)
    references app.notification_deliveries (id)
    on delete cascade,

  constraint notification_push_device_deliveries_notification_id_fkey
    foreign key (notification_id)
    references app.notifications (id)
    on delete cascade,

  constraint notification_push_device_deliveries_device_id_fkey
    foreign key (device_id)
    references app.user_devices (id),

  constraint notification_push_device_deliveries_delivery_device_key
    unique (delivery_id, device_id),

  constraint notification_push_device_deliveries_status_check
    check (status in ('pending', 'sent', 'failed')),

  constraint notification_push_device_deliveries_attempts_check
    check (attempts >= 0)
);

create index notification_push_device_deliveries_pending_idx
  on app.notification_push_device_deliveries (status, attempts, id)
  where status = 'pending';

create index notification_push_device_deliveries_delivery_idx
  on app.notification_push_device_deliveries (delivery_id, status);

comment on table app.notification_push_device_deliveries is
  'Per-device push delivery status. Push dispatch must be idempotent per notification delivery and user device.';
