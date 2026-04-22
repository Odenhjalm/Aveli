create or replace function app.compute_course_next_unlock_at(
  p_course_id uuid,
  p_drip_started_at timestamptz,
  p_current_unlock_position integer
)
returns timestamptz
language plpgsql
stable
set search_path = pg_catalog, app
as $$
declare
  v_drip_mode text;
  v_next_lesson_position integer := 0;
  v_drip_interval_days integer;
  v_custom_unlock_offset_days integer;
begin
  if p_course_id is null then
    raise exception 'next unlock projection requires course id';
  end if;

  if p_drip_started_at is null then
    raise exception 'next unlock projection requires drip_started_at';
  end if;

  if p_current_unlock_position is null then
    raise exception 'next unlock projection requires current_unlock_position';
  end if;

  select coalesce(min(l.position), 0)::integer
    into v_next_lesson_position
  from app.lessons as l
  where l.course_id = p_course_id
    and l.position > p_current_unlock_position;

  if v_next_lesson_position = 0 then
    return null;
  end if;

  v_drip_mode := app.resolve_course_drip_mode(p_course_id);

  if v_drip_mode = 'no_drip_immediate_access' then
    return null;
  end if;

  if v_drip_mode = 'custom_lesson_offsets' then
    select offsets.unlock_offset_days
      into v_custom_unlock_offset_days
    from app.lessons as l
    join app.course_custom_drip_lesson_offsets as offsets
      on offsets.lesson_id = l.id
     and offsets.course_id = p_course_id
    where l.course_id = p_course_id
      and l.position = v_next_lesson_position
    order by l.id
    limit 1;

    if v_custom_unlock_offset_days is null then
      raise exception
        'custom drip course % missing unlock offset for lesson position %',
        p_course_id,
        v_next_lesson_position;
    end if;

    return p_drip_started_at
      + pg_catalog.make_interval(days => v_custom_unlock_offset_days);
  end if;

  select c.drip_interval_days
    into v_drip_interval_days
  from app.courses as c
  where c.id = p_course_id;

  if not found then
    raise exception 'course % does not exist', p_course_id;
  end if;

  if v_drip_interval_days is null or v_drip_interval_days <= 0 then
    raise exception 'drip-enabled course % requires positive drip_interval_days',
      p_course_id;
  end if;

  return p_drip_started_at
    + pg_catalog.make_interval(
      days => (v_next_lesson_position - 1) * v_drip_interval_days
    );
end;
$$;

revoke all on function app.compute_course_next_unlock_at(
  uuid,
  timestamptz,
  integer
) from public;

comment on function app.compute_course_next_unlock_at(
  uuid,
  timestamptz,
  integer
) is
  'Returns the exact learner-safe timestamp for the next locked lesson derived from canonical drip state. Returns null when no later lesson remains locked.';
