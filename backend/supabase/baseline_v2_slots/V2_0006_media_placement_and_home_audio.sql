create table app.lesson_media (
  id uuid not null default gen_random_uuid(),
  lesson_id uuid not null,
  media_asset_id uuid not null,
  position integer not null,
  constraint lesson_media_pkey primary key (id),
  constraint lesson_media_lesson_id_fkey
    foreign key (lesson_id) references app.lessons (id) on delete cascade,
  constraint lesson_media_media_asset_id_fkey
    foreign key (media_asset_id) references app.media_assets (id),
  constraint lesson_media_lesson_id_position_key unique (lesson_id, position),
  constraint lesson_media_position_check check (position >= 1)
);

create index lesson_media_lesson_id_idx
  on app.lesson_media (lesson_id);

create index lesson_media_media_asset_id_idx
  on app.lesson_media (media_asset_id);

comment on table app.lesson_media is
  'Canonical lesson-media placement source. Defines which media assets belong to a lesson and in what order.';

comment on column app.lesson_media.position is
  'Explicit ordering of media within a lesson.';

create or replace function app.enforce_lesson_media_asset_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_purpose app.media_purpose;
begin
  select purpose into v_purpose
  from app.media_assets
  where id = new.media_asset_id;

  if not found then
    raise exception 'lesson media asset % does not exist', new.media_asset_id;
  end if;

  if v_purpose <> 'lesson_media'::app.media_purpose then
    raise exception 'lesson media must have purpose lesson_media';
  end if;

  return new;
end;
$$;

create trigger lesson_media_asset_contract
before insert or update of media_asset_id
on app.lesson_media
for each row
execute function app.enforce_lesson_media_asset_contract();

create table app.home_player_uploads (
  id uuid not null default gen_random_uuid(),
  teacher_id uuid not null,
  media_asset_id uuid not null,
  title text not null,
  active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint home_player_uploads_pkey primary key (id),
  constraint home_player_uploads_teacher_id_fkey
    foreign key (teacher_id) references app.auth_subjects (user_id),
  constraint home_player_uploads_media_asset_id_fkey
    foreign key (media_asset_id) references app.media_assets (id),
  constraint home_player_uploads_title_not_blank_check
    check (btrim(title) <> '')
);

create index home_player_uploads_teacher_id_idx
  on app.home_player_uploads (teacher_id);

create index home_player_uploads_media_asset_id_idx
  on app.home_player_uploads (media_asset_id);

comment on table app.home_player_uploads is
  'Direct home-player audio source owned by teacher_id. Independent from courses.';

create or replace function app.enforce_home_player_upload_asset_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_purpose app.media_purpose;
  v_type app.media_type;
begin
  select purpose, media_type
    into v_purpose, v_type
  from app.media_assets
  where id = new.media_asset_id;

  if not found then
    raise exception 'home player media asset % does not exist', new.media_asset_id;
  end if;

  if v_purpose <> 'home_player_audio'::app.media_purpose then
    raise exception 'home player media must have purpose home_player_audio';
  end if;

  if v_type <> 'audio'::app.media_type then
    raise exception 'home player media must be audio';
  end if;

  return new;
end;
$$;

create trigger home_player_upload_asset_contract
before insert or update of media_asset_id
on app.home_player_uploads
for each row
execute function app.enforce_home_player_upload_asset_contract();

create table app.home_player_course_links (
  id uuid not null default gen_random_uuid(),
  lesson_media_id uuid not null,
  title text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint home_player_course_links_pkey primary key (id),
  constraint home_player_course_links_lesson_media_id_fkey
    foreign key (lesson_media_id) references app.lesson_media (id) on delete cascade,
  constraint home_player_course_links_lesson_media_key unique (lesson_media_id),
  constraint home_player_course_links_title_not_blank_check
    check (btrim(title) <> '')
);

create index home_player_course_links_enabled_idx
  on app.home_player_course_links (enabled)
  where enabled = true;

comment on table app.home_player_course_links is
  'Canonical inclusion table for exposing lesson media as home-player audio. Source-driven inclusion only.';

create or replace function app.enforce_home_player_course_link_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_media_type app.media_type;
  v_media_purpose app.media_purpose;
begin
  select ma.media_type, ma.purpose
    into v_media_type, v_media_purpose
  from app.lesson_media as lm
  join app.media_assets as ma
    on ma.id = lm.media_asset_id
  where lm.id = new.lesson_media_id;

  if not found then
    raise exception 'lesson_media % not found for home_player link', new.lesson_media_id;
  end if;

  if v_media_type <> 'audio'::app.media_type then
    raise exception 'home-player course links require audio media';
  end if;

  if v_media_purpose <> 'lesson_media'::app.media_purpose then
    raise exception 'home-player course links require lesson_media purpose';
  end if;

  return new;
end;
$$;

create trigger home_player_course_link_contract
before insert or update of lesson_media_id
on app.home_player_course_links
for each row
execute function app.enforce_home_player_course_link_contract();
