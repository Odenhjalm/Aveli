-- 20260201130000_flatten_lessons_remove_modules.sql
-- Flatten lessons directly under courses and remove modules.

begin;

-- Ensure course_id exists and backfill from modules.
alter table app.lessons
  add column if not exists course_id uuid;

do $$
begin
  if to_regclass('app.modules') is not null
     and exists (
       select 1
       from information_schema.columns
       where table_schema = 'app'
         and table_name = 'lessons'
         and column_name = 'module_id'
     )
  then
    update app.lessons l
       set course_id = m.course_id
      from app.modules m
     where l.course_id is null
       and l.module_id = m.id;

    -- Re-number positions per course to avoid collisions when dropping modules.
    with ordered as (
      select
        l.id,
        row_number() over (
          partition by m.course_id
          order by m.position, l.position, l.created_at, l.id
        ) as new_position
      from app.lessons l
      join app.modules m on m.id = l.module_id
    )
    update app.lessons l
       set position = o.new_position
      from ordered o
     where l.id = o.id;
  end if;
end $$;

alter table app.lessons
  alter column course_id set not null;

-- Switch uniqueness from module-based ordering to course-based ordering.
alter table app.lessons
  drop constraint if exists lessons_module_id_position_key;

alter table app.lessons
  drop constraint if exists lessons_course_id_position_key;

alter table app.lessons
  add constraint lessons_course_id_position_key unique (course_id, position);

-- Course FK now owned by lessons directly.
alter table app.lessons
  drop constraint if exists lessons_course_id_fkey;

alter table app.lessons
  add constraint lessons_course_id_fkey
  foreign key (course_id) references app.courses(id) on delete cascade;

drop index if exists app.idx_lessons_module;
create index if not exists idx_lessons_course on app.lessons(course_id);

-- Update dependent view to avoid modules.
create or replace view app.v_meditation_audio_library as
  select
    lm.id as media_id,
    l.course_id,
    l.id as lesson_id,
    l.title,
    null::text as description,
    coalesce(mo.storage_path, lm.storage_path) as storage_path,
    coalesce(mo.storage_bucket, lm.storage_bucket, 'lesson-media'::text) as storage_bucket,
    lm.duration_seconds,
    lm.created_at
  from app.lesson_media lm
  join app.lessons l on l.id = lm.lesson_id
  left join app.media_objects mo on mo.id = lm.media_id
  where lower(lm.kind) = 'audio'::text;

-- Update RLS policies to reference course_id instead of modules.
drop policy if exists lessons_select on app.lessons;
create policy lessons_select on app.lessons
  for select to authenticated
  using (
    exists (
      select 1
      from app.courses c
      where c.id = course_id
        and (
          c.created_by = auth.uid()
          or app.is_admin(auth.uid())
          or (c.is_published and (is_intro = true))
          or exists (
            select 1
            from app.enrollments e
            where e.course_id = c.id
              and e.user_id = auth.uid()
          )
        )
    )
  );

drop policy if exists lessons_write on app.lessons;
create policy lessons_write on app.lessons
  for all to authenticated
  using (
    exists (
      select 1
      from app.courses c
      where c.id = course_id
        and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
  )
  with check (
    exists (
      select 1
      from app.courses c
      where c.id = course_id
        and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
  );

drop policy if exists lesson_media_select on app.lesson_media;
create policy lesson_media_select on app.lesson_media
  for select to authenticated
  using (
    exists (
      select 1
      from app.lessons l
      join app.courses c on c.id = l.course_id
      where l.id = lesson_id
        and (
          c.created_by = auth.uid()
          or app.is_admin(auth.uid())
          or (c.is_published and (l.is_intro = true))
          or exists (
            select 1
            from app.enrollments e
            where e.course_id = c.id
              and e.user_id = auth.uid()
          )
        )
    )
  );

drop policy if exists lesson_media_write on app.lesson_media;
create policy lesson_media_write on app.lesson_media
  for all to authenticated
  using (
    exists (
      select 1
      from app.lessons l
      join app.courses c on c.id = l.course_id
      where l.id = lesson_id
        and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
  )
  with check (
    exists (
      select 1
      from app.lessons l
      join app.courses c on c.id = l.course_id
      where l.id = lesson_id
        and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
  );

do $$
begin
  if to_regclass('app.lesson_packages') is not null then
    drop policy if exists lesson_packages_owner on app.lesson_packages;
    create policy lesson_packages_owner on app.lesson_packages
      for all to authenticated
      using (
        exists (
          select 1
          from app.lessons l
          join app.courses c on c.id = l.course_id
          where l.id = lesson_id
            and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
        )
      )
      with check (
        exists (
          select 1
          from app.lessons l
          join app.courses c on c.id = l.course_id
          where l.id = lesson_id
            and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
        )
      );
  end if;
end $$;

-- Remove modules.
alter table app.lessons
  drop column if exists module_id;

drop table if exists app.modules cascade;

commit;

