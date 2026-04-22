-- Slot 0024 promotes canonical course-family authority into app.course_families
-- while preserving the zero-based contiguous family ordering enforced by 0023.
-- app.courses.group_position remains the only ordering authority.

create table if not exists app.course_families (
  id uuid not null default gen_random_uuid(),
  name text not null,
  teacher_id uuid not null,
  created_at timestamptz not null default now(),

  constraint course_families_pkey primary key (id),

  constraint course_families_teacher_id_fkey
    foreign key (teacher_id) references app.auth_subjects (user_id) on delete cascade,

  constraint course_families_name_not_blank_check
    check (btrim(name) <> '')
);

create index if not exists course_families_teacher_id_idx
  on app.course_families (teacher_id);

comment on table app.course_families is
  'Canonical course-family authority. Families may exist before they contain courses.';

comment on column app.course_families.id is
  'Canonical course-family identity referenced by app.courses.course_group_id.';

comment on column app.course_families.name is
  'Teacher-authored display name for a course family.';

comment on column app.course_families.teacher_id is
  'Canonical owner of the course family.';

do $$
declare
  v_conflicting_family uuid;
begin
  select c.course_group_id
    into v_conflicting_family
  from app.courses as c
  group by c.course_group_id
  having count(distinct c.teacher_id) > 1
  limit 1;

  if v_conflicting_family is not null then
    raise exception
      'course family % cannot be backfilled because it spans multiple teachers',
      v_conflicting_family;
  end if;
end;
$$;

insert into app.course_families (
  id,
  name,
  teacher_id,
  created_at
)
select seeded.course_group_id,
       seeded.name,
       seeded.teacher_id,
       seeded.created_at
from (
  select distinct on (c.course_group_id)
         c.course_group_id,
         coalesce(nullif(btrim(c.title), ''), 'Course Family') as name,
         c.teacher_id,
         min(c.created_at) over (partition by c.course_group_id) as created_at
    from app.courses as c
   order by c.course_group_id,
            c.group_position asc,
            c.id asc
) as seeded
on conflict (id) do nothing;

do $$
begin
  if exists (
    select 1
      from pg_constraint
     where conname = 'courses_course_group_id_fkey'
       and conrelid = 'app.courses'::regclass
  ) then
    return;
  end if;

  alter table app.courses
    add constraint courses_course_group_id_fkey
      foreign key (course_group_id) references app.course_families (id);
end;
$$;

create or replace function app.ensure_course_family_row_for_course_write()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_teacher_id uuid;
begin
  select teacher_id
    into v_teacher_id
  from app.course_families
  where id = new.course_group_id;

  if not found then
    insert into app.course_families (
      id,
      name,
      teacher_id,
      created_at
    )
    values (
      new.course_group_id,
      coalesce(nullif(btrim(new.title), ''), 'Course Family'),
      new.teacher_id,
      coalesce(new.created_at, now())
    );

    return new;
  end if;

  if v_teacher_id <> new.teacher_id then
    raise exception
      'course family % belongs to a different teacher',
      new.course_group_id;
  end if;

  return new;
end;
$$;

drop trigger if exists courses_ensure_course_family_row
  on app.courses;

create trigger courses_ensure_course_family_row
before insert or update of course_group_id, teacher_id, title
on app.courses
for each row
execute function app.ensure_course_family_row_for_course_write();

comment on column app.courses.course_group_id is
  'Canonical course-family link to app.course_families.id.';
