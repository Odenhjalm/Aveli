grant usage on schema app to public;

grant select on table app.courses to public;
grant select on table app.lessons to public;
grant select on table app.lesson_media to public;
grant select on table app.media_assets to public;
grant select on table app.course_enrollments to public;
grant select on table app.runtime_media to public;

alter table app.courses enable row level security;
alter table app.lessons enable row level security;
alter table app.lesson_media enable row level security;
alter table app.media_assets enable row level security;
alter table app.course_enrollments enable row level security;

alter view app.runtime_media
  set (security_invoker = true);

create policy course_enrollments_select_self
on app.course_enrollments
for select
to public
using (
  user_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
);

create policy courses_select_enrolled
on app.courses
for select
to public
using (
  exists (
    select 1
    from app.course_enrollments as ce
    where ce.course_id = courses.id
      and ce.user_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  )
);

create policy lessons_select_unlocked
on app.lessons
for select
to public
using (
  exists (
    select 1
    from app.course_enrollments as ce
    where ce.course_id = lessons.course_id
      and ce.user_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      and lessons.position <= ce.current_unlock_position
  )
);

create policy lesson_media_select_unlocked
on app.lesson_media
for select
to public
using (
  exists (
    select 1
    from app.lessons as l
    join app.course_enrollments as ce
      on ce.course_id = l.course_id
    where l.id = lesson_media.lesson_id
      and ce.user_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      and l.position <= ce.current_unlock_position
  )
);

create policy media_assets_select_visible
on app.media_assets
for select
to public
using (
  (
    media_assets.purpose = 'course_cover'::app.media_purpose
    and exists (
      select 1
      from app.courses as c
      join app.course_enrollments as ce
        on ce.course_id = c.id
      where c.cover_media_id = media_assets.id
        and ce.user_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    )
  )
  or (
    media_assets.purpose = 'lesson_media'::app.media_purpose
    and exists (
      select 1
      from app.lesson_media as lm
      join app.lessons as l
        on l.id = lm.lesson_id
      join app.course_enrollments as ce
        on ce.course_id = l.course_id
      where lm.media_asset_id = media_assets.id
        and ce.user_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
        and l.position <= ce.current_unlock_position
    )
  )
);
