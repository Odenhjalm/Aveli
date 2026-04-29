insert into app.course_public_content (
  course_id,
  short_description,
  description
)
select
  c.id,
  'Pending public summary',
  ''
from app.courses as c
where not exists (
  select 1
  from app.course_public_content as cpc
  where cpc.course_id = c.id
);

create or replace function app.ensure_course_public_content_sibling()
returns trigger
language plpgsql
security definer
set search_path = app, public
as $$
begin
  insert into app.course_public_content (
    course_id,
    short_description,
    description
  )
  values (
    new.id,
    'Pending public summary',
    ''
  )
  on conflict (course_id) do nothing;

  return new;
end;
$$;

create trigger courses_course_public_content_sibling
after insert on app.courses
for each row
execute function app.ensure_course_public_content_sibling();

create or replace function app.prevent_course_public_content_parented_delete()
returns trigger
language plpgsql
security definer
set search_path = app, public
as $$
begin
  if pg_trigger_depth() = 1
     and exists (
       select 1
       from app.courses as c
       where c.id = old.course_id
     ) then
    raise exception 'course_public_content cannot be deleted while parent course exists'
      using errcode = '23514';
  end if;

  return old;
end;
$$;

create trigger course_public_content_parented_delete_guard
before delete on app.course_public_content
for each row
execute function app.prevent_course_public_content_parented_delete();

comment on function app.ensure_course_public_content_sibling() is
  'Ensures every newly inserted app.courses row has a sibling app.course_public_content row. The description remains empty until authored through the public-content surface.';

comment on function app.prevent_course_public_content_parented_delete() is
  'Prevents deleting app.course_public_content while its parent app.courses row still exists; parent course deletion may cascade normally.';

comment on trigger courses_course_public_content_sibling on app.courses is
  'Creates the required course_public_content sibling row for each new course.';

comment on trigger course_public_content_parented_delete_guard on app.course_public_content is
  'Guards the course_public_content sibling-row invariant against direct deletion.';

revoke all on function app.ensure_course_public_content_sibling() from public;
revoke all on function app.prevent_course_public_content_parented_delete() from public;
