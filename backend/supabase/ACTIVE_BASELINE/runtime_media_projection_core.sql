-- Phase 3: runtime_media projection boundary
-- runtime_media remains the playback authority only as a read-only projection.
-- It is derived only from canonical source tables:
-- - app.lesson_media
-- - app.lessons
-- - app.media_assets
-- lesson body content remains isolated in app.lesson_contents and is not a
-- runtime_media source.
-- It does not define lesson access.
-- lesson_media remains part of lesson_content_surface only.
-- No independent lesson-media surface exists for learner/public surfaces.
-- Studio has a separate lesson-media edge for authoring and pipeline interaction.
-- Only playback-eligible lesson media may project here.
-- No fallback columns, storage shortcuts, or write paths belong in this view.

create view app.runtime_media
with (security_barrier = true)
as
select
  lm.id as lesson_media_id,
  l.id as lesson_id,
  l.course_id,
  ma.id as media_asset_id,
  ma.media_type,
  ma.playback_object_path,
  ma.playback_format
from app.lesson_media as lm
join app.lessons as l
  on l.id = lm.lesson_id
join app.media_assets as ma
  on ma.id = lm.media_asset_id
where ma.state = 'ready'::app.media_state
  and ma.purpose = 'lesson_media'::app.media_purpose;
