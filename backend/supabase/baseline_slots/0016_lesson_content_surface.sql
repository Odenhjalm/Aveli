create view app.lesson_content_surface
with (security_barrier = true)
as
select
  l.id,
  l.course_id,
  l.lesson_title,
  l.position,
  lc.content_markdown,
  lm.id as lesson_media_id,
  lm.media_asset_id,
  lm.position as lesson_media_position
from app.lessons as l
join app.lesson_contents as lc
  on lc.lesson_id = l.id
left join app.lesson_media as lm
  on lm.lesson_id = l.id
where exists (
  select 1
  from app.course_enrollments as ce
  where ce.course_id = l.course_id
    and ce.user_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and l.position <= ce.current_unlock_position
);

grant select on table app.lesson_content_surface to public;
