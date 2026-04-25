alter type app.course_enrollment_source rename value 'intro_enrollment' to 'intro';

comment on column app.course_enrollments.source is
  'Canonical access source: purchase for premium courses, intro for introduction courses.';

comment on column app.courses.required_enrollment_source is
  'Canonical protected course enrollment source: purchase for premium courses, intro for introduction courses, null before classification.';

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
  v_existing_intro record;
  v_completed_lessons integer := 0;
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

  if p_source = 'intro'::app.course_enrollment_source then
    perform 1
    from app.auth_subjects
    where user_id = p_user_id
    for update;

    if not found then
      raise exception
        'auth subject % does not exist',
        p_user_id;
    end if;
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

  if p_source = 'intro'::app.course_enrollment_source then
    if v_max_lesson_position <= 0 then
      raise exception
        'intro course % requires at least one lesson before enrollment',
        p_course_id;
    end if;

    if exists (
      select 1
      from app.course_enrollments
      where user_id = p_user_id
        and course_id = p_course_id
    ) then
      raise exception
        'user % already has an intro enrollment for course %',
        p_user_id,
        p_course_id;
    end if;

    for v_existing_intro in
      select
        ce.id,
        ce.course_id,
        ce.current_unlock_position,
        coalesce(max(l.position), 0)::integer as max_lesson_position,
        count(l.id)::integer as lesson_count
      from app.course_enrollments as ce
      join app.courses as c
        on c.id = ce.course_id
      left join app.lessons as l
        on l.course_id = ce.course_id
      where ce.user_id = p_user_id
        and c.required_enrollment_source = 'intro'::app.course_enrollment_source
        and ce.source = c.required_enrollment_source
      group by ce.id, ce.course_id, ce.current_unlock_position
      order by ce.course_id
    loop
      if v_existing_intro.lesson_count <= 0
         or v_existing_intro.max_lesson_position <= 0 then
        raise exception
          'existing intro enrollment % lacks canonical lesson progression state',
          v_existing_intro.id;
      end if;

      if v_existing_intro.current_unlock_position < v_existing_intro.max_lesson_position then
        raise exception
          'intro course selection locked by incomplete drip for course %',
          v_existing_intro.course_id;
      end if;

      select count(*)::integer
        into v_completed_lessons
      from app.lesson_completions as lc
      where lc.user_id = p_user_id
        and lc.course_id = v_existing_intro.course_id;

      if v_completed_lessons < v_existing_intro.lesson_count then
        raise exception
          'intro course selection locked by incomplete lesson completion for course %',
          v_existing_intro.course_id;
      end if;
    end loop;
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

  if p_source = 'intro'::app.course_enrollment_source then
    raise exception
      'intro course enrollment for user % and course % was not created',
      p_user_id,
      p_course_id;
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

  return v_enrollment_row;
end;
$$;

comment on function app.canonical_create_course_enrollment(
  uuid,
  uuid,
  uuid,
  app.course_enrollment_source,
  timestamptz
) is
  'Canonical course enrollment creation authority. Intro enrollments use source = intro and are transactionally guarded by prior drip progression and backend lesson completion state.';
