create or replace view app.runtime_media
with (security_barrier = true)
as
select
  lm.id as lesson_media_id,
  l.id as lesson_id,
  l.course_id,
  ma.id as media_asset_id,
  ma.media_type,
  ma.playback_object_path,
  ma.playback_format,
  ma.state
from app.lesson_media as lm
join app.lessons as l
  on l.id = lm.lesson_id
join app.media_assets as ma
  on ma.id = lm.media_asset_id
where ma.purpose = 'lesson_media'::app.media_purpose

union all

select
  null::uuid as lesson_media_id,
  null::uuid as lesson_id,
  c.id as course_id,
  ma.id as media_asset_id,
  ma.media_type,
  ma.playback_object_path,
  ma.playback_format,
  ma.state
from app.courses as c
join app.media_assets as ma
  on ma.id = c.cover_media_id
where ma.purpose = 'course_cover'::app.media_purpose;

alter view app.runtime_media
  set (security_invoker = true);
