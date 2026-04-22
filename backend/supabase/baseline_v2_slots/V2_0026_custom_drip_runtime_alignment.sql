create or replace function app.resolve_course_drip_mode(
  p_course_id uuid
)
returns text
language plpgsql
stable
set search_path = pg_catalog, app
as $$
declare
  v_drip_enabled boolean;
  v_drip_interval_days integer;
begin
  if p_course_id is null then
    raise exception 'course drip mode resolution requires course id';
  end if;

  select c.drip_enabled, c.drip_interval_days
    into v_drip_enabled, v_drip_interval_days
  from app.courses as c
  where c.id = p_course_id;

  if not found then
    raise exception 'course % does not exist', p_course_id;
  end if;

  if exists (
    select 1
    from app.course_custom_drip_configs
    where course_id = p_course_id
  ) then
    perform app.assert_course_custom_drip_schedule(p_course_id);
    return 'custom_lesson_offsets';
  end if;

  if v_drip_enabled then
    if v_drip_interval_days is null or v_drip_interval_days <= 0 then
      raise exception 'drip-enabled course % requires positive drip_interval_days',
        p_course_id;
    end if;

    return 'legacy_uniform_drip';
  end if;

  if v_drip_interval_days is not null then
    raise exception 'course % with drip disabled requires null drip_interval_days',
      p_course_id;
  end if;

  return 'no_drip_immediate_access';
end;
$$;

comment on function app.resolve_course_drip_mode(uuid) is
  'Resolves canonical course drip mode in priority order: valid custom config, legacy uniform drip, then no-drip immediate access. Invalid custom state fails closed.';

create or replace function app.compute_custom_drip_initial_unlock_position(
  p_course_id uuid
)
returns integer
language plpgsql
stable
set search_path = pg_catalog, app
as $$
declare
  v_initial_unlock_position integer := 0;
begin
  perform app.assert_course_custom_drip_schedule(p_course_id);

  select coalesce(max(l.position), 0)::integer
    into v_initial_unlock_position
  from app.lessons as l
  join app.course_custom_drip_lesson_offsets as offsets
    on offsets.lesson_id = l.id
   and offsets.course_id = p_course_id
  where l.course_id = p_course_id
    and offsets.unlock_offset_days = 0;

  return v_initial_unlock_position;
end;
$$;

comment on function app.compute_custom_drip_initial_unlock_position(uuid) is
  'Returns the highest lesson position unlocked immediately for a valid custom-drip course. Immediate unlock means unlock_offset_days = 0.';

create or replace function app.compute_custom_drip_unlock_position(
  p_course_id uuid,
  p_drip_started_at timestamptz,
  p_evaluated_at timestamptz
)
returns integer
language plpgsql
stable
set search_path = pg_catalog, app
as $$
declare
  v_elapsed_days integer := 0;
  v_unlock_position integer := 0;
begin
  if p_course_id is null then
    raise exception 'custom drip unlock computation requires course id';
  end if;

  if p_drip_started_at is null then
    raise exception 'custom drip unlock computation requires drip_started_at';
  end if;

  if p_evaluated_at is null then
    raise exception 'custom drip unlock computation requires evaluated_at';
  end if;

  perform app.assert_course_custom_drip_schedule(p_course_id);

  v_elapsed_days := greatest(
    0,
    floor(
      extract(epoch from (p_evaluated_at - p_drip_started_at)) / 86400.0
    )::integer
  );

  select coalesce(max(l.position), 0)::integer
    into v_unlock_position
  from app.lessons as l
  join app.course_custom_drip_lesson_offsets as offsets
    on offsets.lesson_id = l.id
   and offsets.course_id = p_course_id
  where l.course_id = p_course_id
    and offsets.unlock_offset_days <= v_elapsed_days;

  return v_unlock_position;
end;
$$;

comment on function app.compute_custom_drip_unlock_position(uuid, timestamptz, timestamptz) is
  'Returns the highest lesson position unlocked for a valid custom-drip course at the evaluation timestamp.';

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
  v_required_enrollment_source app.course_enrollment_source;
  v_drip_mode text;
  v_max_lesson_position integer := 0;
  v_initial_unlock_position integer := 0;
  v_enrollment_row app.course_enrollments%rowtype;
begin
  if p_enrollment_id is null then
    raise exception
      'canonical course enrollment creation requires an explicit enrollment id';
  end if;

  if p_user_id is null then
    raise exception
      'canonical course enrollment creation requires an explicit user id';
  end if;

  if p_course_id is null then
    raise exception
      'canonical course enrollment creation requires an explicit course id';
  end if;

  if p_source is null then
    raise exception
      'canonical course enrollment creation requires an explicit source';
  end if;

  if p_granted_at is null then
    raise exception
      'canonical course enrollment creation requires an explicit granted_at';
  end if;

  select
    c.required_enrollment_source,
    coalesce(max(l.position), 0)::integer
  into
    v_required_enrollment_source,
    v_max_lesson_position
  from app.courses as c
  left join app.lessons as l
    on l.course_id = c.id
  where c.id = p_course_id
  group by c.id, c.required_enrollment_source;

  if not found then
    raise exception
      'courses row % does not exist',
      p_course_id;
  end if;

  if v_required_enrollment_source is null then
    raise exception
      'course % lacks required enrollment source',
      p_course_id;
  end if;

  if p_source <> v_required_enrollment_source then
    raise exception
      'course % requires enrollment source %',
      p_course_id,
      v_required_enrollment_source;
  end if;

  v_drip_mode := app.resolve_course_drip_mode(p_course_id);

  v_initial_unlock_position := case
    when v_drip_mode = 'custom_lesson_offsets' then
      app.compute_custom_drip_initial_unlock_position(p_course_id)
    when v_max_lesson_position = 0 then 0
    when v_drip_mode = 'legacy_uniform_drip' then 1
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

    perform pg_catalog.set_config(
      'app.canonical_enrollment_function_context',
      'off',
      true
    );
  exception
    when others then
      perform pg_catalog.set_config(
        'app.canonical_enrollment_function_context',
        'off',
        true
      );
      raise;
  end;

  if v_enrollment_row.id is not null then
    return v_enrollment_row;
  end if;

  select *
  into v_enrollment_row
  from app.course_enrollments
  where user_id = p_user_id
    and course_id = p_course_id;

  if v_enrollment_row.id is null then
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

comment on function app.canonical_create_course_enrollment(
  uuid,
  uuid,
  uuid,
  app.course_enrollment_source,
  timestamptz
) is
  'Canonical enrollment creation authority. Initializes current_unlock_position from the resolved course drip mode and always sets drip_started_at = granted_at.';

create or replace function app.canonical_worker_advance_course_enrollment_drip(
  p_enrollment_id uuid,
  p_evaluated_at timestamptz default clock_timestamp()
)
returns app.course_enrollments
language plpgsql
security definer
set search_path = pg_catalog, app
as $$
declare
  v_enrollment app.course_enrollments%rowtype;
  v_drip_mode text;
  v_drip_interval_days integer;
  v_max_lesson_position integer := 0;
  v_elapsed_intervals integer := 0;
  v_computed_unlock_position integer := 0;
begin
  if p_enrollment_id is null then
    raise exception 'course enrollment drip advancement requires enrollment id';
  end if;

  if p_evaluated_at is null then
    raise exception 'course enrollment drip advancement requires evaluated_at';
  end if;

  select *
    into v_enrollment
  from app.course_enrollments
  where id = p_enrollment_id
  for update;

  if not found then
    raise exception 'course enrollment % does not exist', p_enrollment_id;
  end if;

  v_drip_mode := app.resolve_course_drip_mode(v_enrollment.course_id);

  if v_drip_mode = 'no_drip_immediate_access' then
    return v_enrollment;
  end if;

  if v_drip_mode = 'custom_lesson_offsets' then
    v_computed_unlock_position := app.compute_custom_drip_unlock_position(
      v_enrollment.course_id,
      v_enrollment.drip_started_at,
      p_evaluated_at
    );
  else
    select
      c.drip_interval_days,
      coalesce(max(l.position), 0)::integer
    into
      v_drip_interval_days,
      v_max_lesson_position
    from app.courses as c
    left join app.lessons as l
      on l.course_id = c.id
    where c.id = v_enrollment.course_id
    group by c.id, c.drip_interval_days;

    if not found then
      raise exception 'course % does not exist for enrollment %',
        v_enrollment.course_id,
        p_enrollment_id;
    end if;

    if v_drip_interval_days is null or v_drip_interval_days <= 0 then
      raise exception 'drip-enabled course % requires positive drip_interval_days',
        v_enrollment.course_id;
    end if;

    if v_max_lesson_position = 0 then
      v_computed_unlock_position := 0;
    else
      v_elapsed_intervals := greatest(
        0,
        floor(
          extract(epoch from (p_evaluated_at - v_enrollment.drip_started_at))
          / (v_drip_interval_days * 86400.0)
        )::integer
      );

      v_computed_unlock_position := least(
        v_max_lesson_position,
        1 + v_elapsed_intervals
      );
    end if;
  end if;

  if v_computed_unlock_position <= v_enrollment.current_unlock_position then
    return v_enrollment;
  end if;

  perform pg_catalog.set_config(
    'app.canonical_worker_function_context',
    'on',
    true
  );

  begin
    update app.course_enrollments
       set current_unlock_position = v_computed_unlock_position,
           updated_at = p_evaluated_at
     where id = p_enrollment_id
    returning * into v_enrollment;

  exception
    when others then
      perform pg_catalog.set_config(
        'app.canonical_worker_function_context',
        'off',
        true
      );
      raise;
  end;

  perform pg_catalog.set_config(
    'app.canonical_worker_function_context',
    'off',
    true
  );

  return v_enrollment;
end;
$$;

revoke all on function app.canonical_worker_advance_course_enrollment_drip(
  uuid,
  timestamptz
) from public;

comment on function app.canonical_worker_advance_course_enrollment_drip(
  uuid,
  timestamptz
) is
  'Canonical worker authority for advancing drip enrollment unlock state under either legacy uniform drip or custom lesson-offset drip. It mutates only app.course_enrollments.current_unlock_position.';
