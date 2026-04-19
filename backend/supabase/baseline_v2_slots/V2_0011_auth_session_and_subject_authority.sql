create table app.refresh_tokens (
  jti uuid not null,
  user_id uuid not null,
  token_hash text not null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_used_at timestamptz,
  rotated_at timestamptz,
  revoked_at timestamptz,
  rotated_from_jti uuid,

  constraint refresh_tokens_pkey primary key (jti),

  constraint refresh_tokens_user_id_fkey
    foreign key (user_id)
    references app.auth_subjects (user_id)
    on delete cascade,

  constraint refresh_tokens_rotated_from_jti_fkey
    foreign key (rotated_from_jti)
    references app.refresh_tokens (jti)
    on delete set null,

  constraint refresh_tokens_token_hash_key unique (token_hash),

  constraint refresh_tokens_token_hash_not_blank_check
    check (btrim(token_hash) <> ''),

  constraint refresh_tokens_expires_after_issued_check
    check (expires_at > issued_at),

  constraint refresh_tokens_revoked_after_issued_check
    check (revoked_at is null or revoked_at >= issued_at),

  constraint refresh_tokens_rotated_after_issued_check
    check (rotated_at is null or rotated_at >= issued_at),

  constraint refresh_tokens_not_self_rotated_check
    check (rotated_from_jti is null or rotated_from_jti <> jti)
);

create index refresh_tokens_user_id_idx
  on app.refresh_tokens (user_id);

create index refresh_tokens_active_idx
  on app.refresh_tokens (user_id, expires_at)
  where revoked_at is null and rotated_at is null;

create index refresh_tokens_rotated_from_jti_idx
  on app.refresh_tokens (rotated_from_jti)
  where rotated_from_jti is not null;

comment on table app.refresh_tokens is
  'Canonical refresh-token session substrate using jti, token hash, rotation, and revocation. It does not own identity or Aveli domain authority.';

comment on column app.refresh_tokens.jti is
  'Refresh-token identifier used as the primary session-token key.';

comment on column app.refresh_tokens.token_hash is
  'Backend-stored hash of the refresh token. Raw refresh tokens must not be persisted.';

comment on column app.refresh_tokens.rotated_from_jti is
  'Optional lineage pointer for deterministic refresh-token rotation.';

create table app.admin_bootstrap_state (
  singleton boolean not null default true,
  consumed_at timestamptz,
  consumed_by_user_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint admin_bootstrap_state_pkey primary key (singleton),

  constraint admin_bootstrap_state_singleton_check
    check (singleton = true),

  constraint admin_bootstrap_state_consumed_by_user_id_fkey
    foreign key (consumed_by_user_id)
    references app.auth_subjects (user_id)
    on delete restrict,

  constraint admin_bootstrap_state_consumed_pair_check
    check (
      (consumed_at is null and consumed_by_user_id is null)
      or
      (consumed_at is not null and consumed_by_user_id is not null)
    )
);

insert into app.admin_bootstrap_state (singleton)
values (true);

comment on table app.admin_bootstrap_state is
  'Singleton operator bootstrap state for the first admin role grant.';

create or replace function app.bootstrap_first_admin(target_user_id uuid)
returns app.auth_subjects
language plpgsql
set search_path = pg_catalog, app, auth
as $$
declare
  v_email text;
  v_subject app.auth_subjects;
  v_consumed_at timestamptz;
begin
  if target_user_id is null then
    raise exception 'target_user_id is required';
  end if;

  select email
    into v_email
  from auth.users
  where id = target_user_id;

  if not found then
    raise exception 'target auth user % does not exist', target_user_id;
  end if;

  insert into app.admin_bootstrap_state (singleton)
  values (true)
  on conflict (singleton) do nothing;

  select consumed_at
    into v_consumed_at
  from app.admin_bootstrap_state
  where singleton = true
  for update;

  if v_consumed_at is not null then
    raise exception 'admin bootstrap has already been consumed';
  end if;

  insert into app.auth_subjects (
    user_id,
    email,
    role,
    onboarding_state,
    created_at,
    updated_at
  )
  values (
    target_user_id,
    v_email,
    'admin'::app.auth_subject_role,
    'incomplete'::app.onboarding_state,
    now(),
    now()
  )
  on conflict (user_id) do update
    set email = coalesce(app.auth_subjects.email, excluded.email),
        role = 'admin'::app.auth_subject_role,
        updated_at = now()
  returning * into v_subject;

  update app.admin_bootstrap_state
     set consumed_at = now(),
         consumed_by_user_id = target_user_id,
         updated_at = now()
   where singleton = true;

  insert into app.auth_events (
    actor_user_id,
    subject_user_id,
    event_type,
    metadata
  )
  values (
    target_user_id,
    target_user_id,
    'admin_bootstrap_consumed',
    '{}'::jsonb
  );

  return v_subject;
end;
$$;

revoke all on function app.bootstrap_first_admin(uuid) from public;

comment on function app.bootstrap_first_admin(uuid) is
  'Operator-controlled bootstrap function that grants the first admin role through app.auth_subjects.role and records observability state.';
