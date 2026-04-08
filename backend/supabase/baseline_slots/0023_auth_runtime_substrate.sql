create table app.refresh_tokens (
  jti uuid not null default extensions.gen_random_uuid(),
  user_id uuid not null,
  token_hash text not null,
  issued_at timestamptz not null default timezone('utc', now()),
  expires_at timestamptz not null,
  last_used_at timestamptz,
  rotated_at timestamptz,
  revoked_at timestamptz,
  rotated_from_jti uuid,
  constraint refresh_tokens_pkey primary key (jti),
  constraint refresh_tokens_token_hash_key unique (token_hash),
  constraint refresh_tokens_expires_at_check check (
    expires_at > issued_at
  ),
  constraint refresh_tokens_last_used_at_check check (
    last_used_at is null or last_used_at >= issued_at
  ),
  constraint refresh_tokens_rotated_at_check check (
    rotated_at is null or rotated_at >= issued_at
  ),
  constraint refresh_tokens_revoked_at_check check (
    revoked_at is null or revoked_at >= issued_at
  ),
  constraint refresh_tokens_rotated_from_jti_check check (
    rotated_from_jti is null or rotated_from_jti <> jti
  ),
  constraint refresh_tokens_rotated_from_jti_fkey
    foreign key (rotated_from_jti) references app.refresh_tokens (jti)
);

create index refresh_tokens_user_id_idx
  on app.refresh_tokens (user_id, expires_at desc);

create index refresh_tokens_rotated_from_jti_idx
  on app.refresh_tokens (rotated_from_jti);

create table app.auth_events (
  event_id uuid not null default extensions.gen_random_uuid(),
  actor_user_id uuid,
  subject_user_id uuid not null,
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  constraint auth_events_pkey primary key (event_id),
  constraint auth_events_event_type_check check (
    event_type in (
      'admin_bootstrap_consumed',
      'onboarding_completed',
      'teacher_role_granted',
      'teacher_role_revoked'
    )
  )
);

create index auth_events_subject_user_id_created_at_idx
  on app.auth_events (subject_user_id, created_at desc);

create index auth_events_event_type_created_at_idx
  on app.auth_events (event_type, created_at desc);

comment on table app.refresh_tokens is
  'Canonical refresh-token persistence supporting rotation lineage, revocation, and auditability.';

comment on table app.auth_events is
  'Canonical Auth + Onboarding audit event surface limited to contracted event families.';
