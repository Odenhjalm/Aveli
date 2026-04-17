create view app.course_discovery_surface
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
  c.drip_interval_days
from app.courses as c
where c.visibility = 'public'::app.course_visibility;

comment on view app.course_discovery_surface is
  'Public course discovery surface. Source authority remains app.courses.';

create view app.lesson_structure_surface
with (security_barrier = true)
as
select
  l.id,
  l.course_id,
  l.lesson_title,
  l.position
from app.lessons as l
join app.courses as c
  on c.id = l.course_id
where c.visibility = 'public'::app.course_visibility;

comment on view app.lesson_structure_surface is
  'Public lesson structure projection. No content or access logic.';

create view app.course_detail_surface
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
  lss.position as lesson_position
from app.course_discovery_surface as cds
left join app.course_public_content as cpc
  on cpc.course_id = cds.id
left join app.lesson_structure_surface as lss
  on lss.course_id = cds.id;

comment on view app.course_detail_surface is
  'Composed public course detail surface. Does not expose lesson content or media.';

create view app.lesson_content_surface
with (security_barrier = true)
as
select
  l.id,
  l.course_id,
  l.lesson_title,
  l.position,
  lc.content_markdown
from app.lessons as l
left join app.lesson_contents as lc
  on lc.lesson_id = l.id;

comment on view app.lesson_content_surface is
  'Protected lesson content surface. Access must be enforced outside the view.';

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
where ma.purpose = 'course_cover'::app.media_purpose

union all

select
  null::uuid as lesson_media_id,
  null::uuid as lesson_id,
  null::uuid as course_id,
  ma.id as media_asset_id,
  ma.media_type,
  ma.playback_object_path,
  ma.playback_format,
  ma.state
from app.home_player_uploads as hpu
join app.media_assets as ma
  on ma.id = hpu.media_asset_id
where hpu.active = true
  and ma.purpose = 'home_player_audio'::app.media_purpose
  and ma.media_type = 'audio'::app.media_type

union all

select
  null::uuid as lesson_media_id,
  null::uuid as lesson_id,
  null::uuid as course_id,
  ma.id as media_asset_id,
  ma.media_type,
  ma.playback_object_path,
  ma.playback_format,
  ma.state
from app.profile_media_placements as pmp
join app.media_assets as ma
  on ma.id = pmp.media_asset_id
where pmp.visibility = 'published'::app.profile_media_visibility
  and ma.purpose = 'profile_media'::app.media_purpose;

comment on view app.runtime_media is
  'Read-only projection of media across the system. Never used as source of truth.';

alter view app.course_discovery_surface set (security_invoker = true);
alter view app.lesson_structure_surface set (security_invoker = true);
alter view app.course_detail_surface set (security_invoker = true);
alter view app.lesson_content_surface set (security_invoker = true);
alter view app.runtime_media set (security_invoker = true);
