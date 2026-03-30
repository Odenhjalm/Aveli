grant usage on schema app to public;

grant select on table app.courses to public;
grant select on table app.lessons to public;
grant select on table app.lesson_contents to public;
grant select on table app.lesson_media to public;
grant select on table app.media_assets to public;
grant select on table app.course_enrollments to public;
grant select on table app.runtime_media to public;

alter table app.courses enable row level security;
alter table app.lessons enable row level security;
alter table app.lesson_contents enable row level security;
alter table app.lesson_media enable row level security;
alter table app.media_assets enable row level security;
alter table app.course_enrollments enable row level security;

alter view app.runtime_media
  set (security_invoker = true);

drop policy if exists course_enrollments_select_self on app.course_enrollments;
create policy course_enrollments_select_self
on app.course_enrollments
for select
to public
using (
  user_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
);

drop policy if exists courses_select_discovery on app.courses;
drop policy if exists courses_select_enrolled on app.courses;
create policy courses_select_discovery
on app.courses
for select
to public
using (true);

drop policy if exists lessons_select_structure on app.lessons;
drop policy if exists lessons_select_unlocked on app.lessons;
create policy lessons_select_structure
on app.lessons
for select
to public
using (true);

drop policy if exists lesson_contents_select_protected on app.lesson_contents;
create policy lesson_contents_select_protected
on app.lesson_contents
for select
to public
using (
  exists (
    select 1
    from app.lessons as l
    join app.courses as c
      on c.id = l.course_id
    join app.course_enrollments as ce
      on ce.course_id = l.course_id
    where l.id = lesson_contents.lesson_id
      and ce.user_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      and (
        (
          c.step = 'intro'::app.course_step
          and ce.source = 'intro_enrollment'::app.course_enrollment_source
        )
        or (
          c.step in (
            'step1'::app.course_step,
            'step2'::app.course_step,
            'step3'::app.course_step
          )
          and ce.source = 'purchase'::app.course_enrollment_source
        )
      )
      and l.position <= ce.current_unlock_position
  )
);

drop policy if exists lesson_media_select_protected on app.lesson_media;
drop policy if exists lesson_media_select_unlocked on app.lesson_media;
create policy lesson_media_select_protected
on app.lesson_media
for select
to public
using (
  exists (
    select 1
    from app.lessons as l
    join app.courses as c
      on c.id = l.course_id
    join app.course_enrollments as ce
      on ce.course_id = l.course_id
    where l.id = lesson_media.lesson_id
      and ce.user_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      and (
        (
          c.step = 'intro'::app.course_step
          and ce.source = 'intro_enrollment'::app.course_enrollment_source
        )
        or (
          c.step in (
            'step1'::app.course_step,
            'step2'::app.course_step,
            'step3'::app.course_step
          )
          and ce.source = 'purchase'::app.course_enrollment_source
        )
      )
      and l.position <= ce.current_unlock_position
  )
);

drop policy if exists media_assets_select_protected_lesson_media on app.media_assets;
drop policy if exists media_assets_select_visible on app.media_assets;
create policy media_assets_select_protected_lesson_media
on app.media_assets
for select
to public
using (
  media_assets.purpose = 'lesson_media'::app.media_purpose
  and exists (
    select 1
    from app.lesson_media as lm
    join app.lessons as l
      on l.id = lm.lesson_id
    join app.courses as c
      on c.id = l.course_id
    join app.course_enrollments as ce
      on ce.course_id = l.course_id
    where lm.media_asset_id = media_assets.id
      and ce.user_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      and (
        (
          c.step = 'intro'::app.course_step
          and ce.source = 'intro_enrollment'::app.course_enrollment_source
        )
        or (
          c.step in (
            'step1'::app.course_step,
            'step2'::app.course_step,
            'step3'::app.course_step
          )
          and ce.source = 'purchase'::app.course_enrollment_source
        )
      )
      and l.position <= ce.current_unlock_position
  )
);
