create table app.course_enrollments (
  id uuid not null,
  user_id uuid not null,
  course_id uuid not null,
  source app.course_enrollment_source not null,
  granted_at timestamptz not null,
  drip_started_at timestamptz not null,
  current_unlock_position integer not null,
  constraint course_enrollments_pkey primary key (id),
  constraint course_enrollments_user_id_course_id_key unique (user_id, course_id),
  constraint course_enrollments_current_unlock_position_check check (
    current_unlock_position >= 0
  ),
  constraint course_enrollments_drip_started_at_check check (
    drip_started_at = granted_at
  ),
  constraint course_enrollments_course_id_fkey
    foreign key (course_id) references app.courses (id)
);

create or replace function app.enforce_course_enrollments_canonical_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  in_enrollment_context boolean :=
    coalesce(current_setting('app.canonical_enrollment_function_context', true), '') = 'on';
  in_worker_context boolean :=
    coalesce(current_setting('app.canonical_worker_function_context', true), '') = 'on';
begin
  if tg_op = 'INSERT' then
    if not in_enrollment_context then
      raise exception
        'course_enrollments rows may be inserted only through the canonical enrollment function';
    end if;

    if new.drip_started_at is distinct from new.granted_at then
      raise exception
        'course_enrollments.drip_started_at must equal granted_at';
    end if;

    return new;
  end if;

  if new.id is distinct from old.id
     or new.user_id is distinct from old.user_id
     or new.course_id is distinct from old.course_id
     or new.source is distinct from old.source
     or new.granted_at is distinct from old.granted_at
     or new.drip_started_at is distinct from old.drip_started_at then
    raise exception
      'canonical course_enrollments identity, source, and anchor fields are immutable';
  end if;

  if new.current_unlock_position is distinct from old.current_unlock_position then
    if not in_worker_context then
      raise exception
        'current_unlock_position may be advanced only through the canonical drip worker function';
    end if;

    if new.current_unlock_position < old.current_unlock_position then
      raise exception
        'canonical drip progression must never decrease current_unlock_position';
    end if;
  end if;

  return new;
end;
$$;

create or replace function app.canonical_create_course_enrollment(
  p_enrollment_id uuid,
  p_user_id uuid,
  p_course_id uuid,
  p_source app.course_enrollment_source,
  p_granted_at timestamptz default clock_timestamp()
)
returns app.course_enrollments
language plpgsql
security definer
set search_path = pg_catalog, app
as $$
declare
  v_course_step app.course_step;
  v_drip_enabled boolean;
  v_max_lesson_position integer := 0;
  v_initial_unlock_position integer := 0;
  v_enrollment_row app.course_enrollments%rowtype;
begin
  if p_enrollment_id is null then
    raise exception
      'canonical course enrollment creation requires an explicit enrollment id';
  end if;

  select
    c.step,
    c.drip_enabled,
    coalesce(max(l.position), 0)::integer
  into
    v_course_step,
    v_drip_enabled,
    v_max_lesson_position
  from app.courses as c
  left join app.lessons as l
    on l.course_id = c.id
  where c.id = p_course_id
  group by c.id, c.step, c.drip_enabled;

  if not found then
    raise exception
      'courses row % does not exist',
      p_course_id;
  end if;

  if v_course_step = 'intro'::app.course_step
     and p_source <> 'intro_enrollment'::app.course_enrollment_source then
    raise exception
      'intro courses require source = intro_enrollment';
  end if;

  if v_course_step in (
       'step1'::app.course_step,
       'step2'::app.course_step,
       'step3'::app.course_step
     )
     and p_source <> 'purchase'::app.course_enrollment_source then
    raise exception
      'paid courses require source = purchase';
  end if;

  v_initial_unlock_position := case
    when v_max_lesson_position = 0 then 0
    when v_drip_enabled then 1
    else v_max_lesson_position
  end;

  perform pg_catalog.set_config(
    'app.canonical_enrollment_function_context',
    'on',
    true
  );

  begin
    insert into app.course_enrollments (
      id,
      user_id,
      course_id,
      source,
      granted_at,
      drip_started_at,
      current_unlock_position
    )
    values (
      p_enrollment_id,
      p_user_id,
      p_course_id,
      p_source,
      p_granted_at,
      p_granted_at,
      v_initial_unlock_position
    )
    on conflict (user_id, course_id) do nothing
    returning * into v_enrollment_row;
  exception
    when others then
      perform pg_catalog.set_config(
        'app.canonical_enrollment_function_context',
        'off',
        true
      );
      raise;
  end;

  perform pg_catalog.set_config(
    'app.canonical_enrollment_function_context',
    'off',
    true
  );

  if v_enrollment_row.id is not null then
    return v_enrollment_row;
  end if;

  select *
  into v_enrollment_row
  from app.course_enrollments
  where user_id = p_user_id
    and course_id = p_course_id;

  if not found then
    raise exception
      'course_enrollments row for user % and course % was not persisted',
      p_user_id,
      p_course_id;
  end if;

  if v_enrollment_row.source is distinct from p_source then
    raise exception
      'existing enrollment source % does not match requested source %',
      v_enrollment_row.source,
      p_source;
  end if;

  return v_enrollment_row;
end;
$$;

revoke all on function app.canonical_create_course_enrollment(
  uuid,
  uuid,
  uuid,
  app.course_enrollment_source,
  timestamptz
) from public;

drop trigger if exists course_enrollments_canonical_contract on app.course_enrollments;

create trigger course_enrollments_canonical_contract
before insert or update on app.course_enrollments
for each row
execute function app.enforce_course_enrollments_canonical_contract();
