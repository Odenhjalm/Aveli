create table app.admin_bootstrap_state (
  bootstrap_key text not null,
  consumed boolean not null default false,
  consumed_at timestamptz,
  target_user_id uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint admin_bootstrap_state_pkey primary key (bootstrap_key),
  constraint admin_bootstrap_state_singleton_check check (
    bootstrap_key = 'first_admin'
  ),
  constraint admin_bootstrap_state_consumed_check check (
    (
      consumed = false
      and consumed_at is null
      and target_user_id is null
    )
    or (
      consumed = true
      and consumed_at is not null
      and target_user_id is not null
    )
  )
);

insert into app.admin_bootstrap_state (
  bootstrap_key
)
values (
  'first_admin'
);

create or replace function app.bootstrap_first_admin(target_user_id uuid)
returns app.auth_subjects
language plpgsql
security definer
set search_path = pg_catalog, app, auth
as $$
declare
  v_target_user_id uuid := target_user_id;
  v_bootstrap_state app.admin_bootstrap_state%rowtype;
  v_subject_row app.auth_subjects%rowtype;
  v_now timestamptz := timezone('utc', now());
begin
  if v_target_user_id is null then
    raise exception
      'bootstrap_first_admin requires target_user_id';
  end if;

  select *
  into v_bootstrap_state
  from app.admin_bootstrap_state
  where bootstrap_key = 'first_admin'
  for update;

  if not found then
    raise exception
      'admin_bootstrap_state is missing the first_admin bootstrap row';
  end if;

  if v_bootstrap_state.consumed then
    raise exception
      'first admin bootstrap has already been consumed';
  end if;

  perform 1
  from auth.users
  where id = v_target_user_id
  for update;

  if not found then
    raise exception
      'bootstrap target auth.users row % does not exist',
      v_target_user_id;
  end if;

  update app.auth_subjects
  set is_admin = true
  where user_id = v_target_user_id
  returning * into v_subject_row;

  if v_subject_row.user_id is null then
    raise exception
      'bootstrap target auth_subjects row % does not exist',
      v_target_user_id;
  end if;

  update app.admin_bootstrap_state
  set consumed = true,
      consumed_at = v_now,
      target_user_id = v_target_user_id,
      updated_at = v_now
  where bootstrap_key = 'first_admin';

  insert into app.auth_events (
    actor_user_id,
    subject_user_id,
    event_type,
    metadata,
    created_at
  )
  values (
    null,
    v_target_user_id,
    'admin_bootstrap_consumed',
    jsonb_build_object(
      'bootstrap_key',
      'first_admin'
    ),
    v_now
  );

  return v_subject_row;
end;
$$;

revoke all on function app.bootstrap_first_admin(uuid) from public;
revoke all on function app.bootstrap_first_admin(uuid) from anon;
revoke all on function app.bootstrap_first_admin(uuid) from authenticated;
revoke all on function app.bootstrap_first_admin(uuid) from service_role;

comment on table app.admin_bootstrap_state is
  'Operator-controlled singleton bootstrap state for the first admin grant.';

comment on function app.bootstrap_first_admin(uuid) is
  'Operator-controlled one-time bootstrap for establishing the first admin. No public route may own this function.';
