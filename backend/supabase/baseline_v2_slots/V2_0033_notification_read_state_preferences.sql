alter table app.notifications
  add column read_at timestamptz;

comment on column app.notifications.read_at is
  'Nullable backend-owned read timestamp for the recipient notification row.';

create index notifications_user_id_read_at_created_at_idx
  on app.notifications (user_id, read_at, created_at desc);

create table app.notification_preferences (
  user_id uuid not null,
  type text not null,
  push_enabled boolean not null,
  in_app_enabled boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint notification_preferences_pkey
    primary key (user_id, type),

  constraint notification_preferences_user_id_fkey
    foreign key (user_id)
    references app.auth_subjects (user_id),

  constraint notification_preferences_type_check
    check (type in ('lesson_drip', 'purchase', 'message'))
);

create index notification_preferences_user_id_idx
  on app.notification_preferences (user_id);

comment on table app.notification_preferences is
  'Backend-authoritative per-user notification channel preferences.';

comment on column app.notification_preferences.push_enabled is
  'User intent for push delivery. Backend channel policy remains authoritative.';

comment on column app.notification_preferences.in_app_enabled is
  'User intent for in-app delivery. Backend channel policy remains authoritative.';
