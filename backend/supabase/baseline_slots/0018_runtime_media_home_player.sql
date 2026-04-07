do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    join pg_enum e on e.enumtypid = t.oid
    where n.nspname = 'app'
      and t.typname = 'media_purpose'
      and e.enumlabel = 'home_player_audio'
  ) then
    alter type app.media_purpose add value 'home_player_audio';
  end if;
end
$$;

create table if not exists app.home_player_uploads (
  id uuid not null,
  teacher_id uuid not null,
  media_asset_id uuid not null,
  active boolean not null default false,
  constraint home_player_uploads_pkey primary key (id),
  constraint home_player_uploads_media_asset_id_fkey
    foreign key (media_asset_id) references app.media_assets (id)
);

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
  and ma.purpose::text = 'home_player_audio'
  and ma.media_type = 'audio'::app.media_type;

alter view app.runtime_media
  set (security_invoker = true);
