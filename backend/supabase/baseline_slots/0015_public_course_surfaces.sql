create view app.course_discovery_surface
with (security_barrier = true)
as
select
  c.id,
  c.slug,
  c.title,
  c.course_group_id,
  c.step,
  c.cover_media_id,
  c.price_amount_cents,
  c.drip_enabled,
  c.drip_interval_days
from app.courses as c;

alter view app.course_discovery_surface
  set (security_invoker = true);

grant select on table app.course_discovery_surface to public;

create view app.lesson_structure_surface
with (security_barrier = true)
as
select
  l.id,
  l.course_id,
  l.lesson_title,
  l.position
from app.lessons as l;

alter view app.lesson_structure_surface
  set (security_invoker = true);

grant select on table app.lesson_structure_surface to public;

create view app.course_detail_surface
with (security_barrier = true)
as
select
  cds.id,
  cds.slug,
  cds.title,
  cds.course_group_id,
  cds.step,
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

alter view app.course_detail_surface
  set (security_invoker = true);

grant select on table app.course_detail_surface to public;
