-- Local HOME_AUDIO_RUNTIME integration alignment.
-- This patch is intentionally minimal and only adds the source tables,
-- visibility helpers, and compatibility columns already required by the
-- canonical home-audio read/write paths.

create extension if not exists pgcrypto;

alter type app.media_purpose add value if not exists 'lesson_audio';
alter type app.media_purpose add value if not exists 'home_player_audio';

create or replace function app.is_test_row_visible(
  p_is_test boolean,
  p_test_session_id uuid
)
returns boolean
language sql
stable
as $$
  select case
    when coalesce(p_is_test, false) = false then true
    when nullif(current_setting('app.test_session_id', true), '') is null then false
    else p_test_session_id = nullif(current_setting('app.test_session_id', true), '')::uuid
  end
$$;

alter table app.courses
  add column if not exists created_by uuid,
  add column if not exists is_published boolean not null default false,
  add column if not exists is_test boolean not null default false,
  add column if not exists test_session_id uuid;

alter table app.lessons
  add column if not exists is_test boolean not null default false,
  add column if not exists test_session_id uuid;

alter table app.lesson_media
  add column if not exists is_test boolean not null default false,
  add column if not exists test_session_id uuid;

alter table app.media_assets
  add column if not exists owner_id uuid,
  add column if not exists course_id uuid,
  add column if not exists lesson_id uuid,
  add column if not exists original_content_type text,
  add column if not exists original_filename text,
  add column if not exists original_size_bytes bigint,
  add column if not exists storage_bucket text not null default 'course-media',
  add column if not exists streaming_object_path text,
  add column if not exists streaming_format text,
  add column if not exists duration_seconds integer,
  add column if not exists codec text,
  add column if not exists error_message text,
  add column if not exists processing_attempts integer not null default 0,
  add column if not exists processing_locked_at timestamptz,
  add column if not exists next_retry_at timestamptz,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists streaming_storage_bucket text;

create table if not exists app.home_player_course_links (
  id uuid not null default gen_random_uuid(),
  teacher_id uuid not null,
  lesson_media_id uuid,
  title text not null,
  course_title_snapshot text not null default ''::text,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint home_player_course_links_pkey primary key (id)
);

create table if not exists app.home_player_uploads (
  id uuid not null default gen_random_uuid(),
  teacher_id uuid not null,
  media_id uuid,
  title text not null,
  kind text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  media_asset_id uuid,
  constraint home_player_uploads_pkey primary key (id),
  constraint home_player_uploads_kind_check check (kind = any (array['audio'::text, 'video'::text])),
  constraint home_player_uploads_media_ref_check check (((media_id is null) <> (media_asset_id is null)))
);

create unique index if not exists home_player_course_links_teacher_id_lesson_media_id_key
on app.home_player_course_links (teacher_id, lesson_media_id);

create index if not exists idx_home_player_course_links_teacher_created
on app.home_player_course_links (teacher_id, created_at desc);

create index if not exists idx_home_player_uploads_media_asset
on app.home_player_uploads (media_asset_id);

create index if not exists idx_home_player_uploads_teacher_created
on app.home_player_uploads (teacher_id, created_at desc);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'courses_created_by_fkey'
      and conrelid = 'app.courses'::regclass
  ) then
    alter table app.courses
      add constraint courses_created_by_fkey
      foreign key (created_by) references app.profiles(user_id) on delete set null;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'media_assets_owner_id_fkey'
      and conrelid = 'app.media_assets'::regclass
  ) then
    alter table app.media_assets
      add constraint media_assets_owner_id_fkey
      foreign key (owner_id) references app.profiles(user_id) on delete set null;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'media_assets_course_id_fkey'
      and conrelid = 'app.media_assets'::regclass
  ) then
    alter table app.media_assets
      add constraint media_assets_course_id_fkey
      foreign key (course_id) references app.courses(id) on delete set null;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'media_assets_lesson_id_fkey'
      and conrelid = 'app.media_assets'::regclass
  ) then
    alter table app.media_assets
      add constraint media_assets_lesson_id_fkey
      foreign key (lesson_id) references app.lessons(id) on delete set null;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'home_player_course_links_teacher_id_fkey'
      and conrelid = 'app.home_player_course_links'::regclass
  ) then
    alter table app.home_player_course_links
      add constraint home_player_course_links_teacher_id_fkey
      foreign key (teacher_id) references app.profiles(user_id) on delete cascade;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'home_player_course_links_lesson_media_id_fkey'
      and conrelid = 'app.home_player_course_links'::regclass
  ) then
    alter table app.home_player_course_links
      add constraint home_player_course_links_lesson_media_id_fkey
      foreign key (lesson_media_id) references app.lesson_media(id) on delete set null;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'home_player_uploads_teacher_id_fkey'
      and conrelid = 'app.home_player_uploads'::regclass
  ) then
    alter table app.home_player_uploads
      add constraint home_player_uploads_teacher_id_fkey
      foreign key (teacher_id) references app.profiles(user_id) on delete cascade;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'home_player_uploads_media_asset_id_fkey'
      and conrelid = 'app.home_player_uploads'::regclass
  ) then
    alter table app.home_player_uploads
      add constraint home_player_uploads_media_asset_id_fkey
      foreign key (media_asset_id) references app.media_assets(id);
  end if;
end $$;
