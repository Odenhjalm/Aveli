alter table app.courses
  add column required_enrollment_source app.course_enrollment_source;

comment on column app.courses.required_enrollment_source is
  'Canonical course access classification. Null means protected access fails closed.';

alter table app.courses
  add constraint courses_public_requires_access_classification_check
  check (
    visibility <> 'public'::app.course_visibility
    or required_enrollment_source is not null
  );

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
    c.required_enrollment_source,
    c.drip_enabled,
    coalesce(max(l.position), 0)::integer
  into
    v_required_enrollment_source,
    v_drip_enabled,
    v_max_lesson_position
  from app.courses as c
  left join app.lessons as l
    on l.course_id = c.id
  where c.id = p_course_id
  group by c.id, c.required_enrollment_source, c.drip_enabled;

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

create or replace view app.course_discovery_surface
with (security_barrier = true)
as
select
  c.id,
  c.slug,
  c.title,
  c.course_group_id,
  c.group_position,
  c.cover_media_id,
  c.price_amount_cents,
  c.drip_enabled,
  c.drip_interval_days,
  c.required_enrollment_source
from app.courses as c
where c.visibility = 'public'::app.course_visibility;

comment on view app.course_discovery_surface is
  'Public course discovery surface. Source authority remains app.courses.';

create or replace view app.course_detail_surface
with (security_barrier = true)
as
select
  cds.id,
  cds.slug,
  cds.title,
  cds.course_group_id,
  cds.group_position,
  cds.cover_media_id,
  cds.price_amount_cents,
  cds.drip_enabled,
  cds.drip_interval_days,
  cpc.short_description,
  lss.id as lesson_id,
  lss.lesson_title,
  lss.position as lesson_position,
  cds.required_enrollment_source
from app.course_discovery_surface as cds
left join app.course_public_content as cpc
  on cpc.course_id = cds.id
left join app.lesson_structure_surface as lss
  on lss.course_id = cds.id;

comment on view app.course_detail_surface is
  'Composed public course detail surface. Does not expose lesson content or media.';
