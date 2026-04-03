alter type app.media_purpose add value if not exists 'home_player_audio';

alter table app.media_assets
  add column if not exists owner_id uuid,
  add column if not exists course_id uuid,
  add column if not exists lesson_id uuid,
  add column if not exists original_content_type text,
  add column if not exists original_filename text,
  add column if not exists original_size_bytes bigint,
  add column if not exists storage_bucket text not null default 'course-media',
  add column if not exists streaming_storage_bucket text,
  add column if not exists streaming_object_path text,
  add column if not exists streaming_format text,
  add column if not exists duration_seconds integer,
  add column if not exists codec text,
  add column if not exists error_message text,
  add column if not exists processing_attempts integer not null default 0,
  add column if not exists processing_locked_at timestamptz,
  add column if not exists next_retry_at timestamptz,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

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
      foreign key (owner_id) references app.profiles (user_id) on delete set null;
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
      foreign key (course_id) references app.courses (id) on delete set null;
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
      foreign key (lesson_id) references app.lessons (id) on delete set null;
  end if;
end $$;

create table app.home_player_uploads (
  id uuid not null default extensions.gen_random_uuid(),
  teacher_id uuid not null,
  media_id uuid,
  media_asset_id uuid,
  title text not null,
  kind text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint home_player_uploads_pkey primary key (id),
  constraint home_player_uploads_kind_check
    check (kind = any (array['audio'::text, 'video'::text])),
  constraint home_player_uploads_media_ref_check
    check ((media_id is null) <> (media_asset_id is null)),
  constraint home_player_uploads_teacher_id_fkey
    foreign key (teacher_id) references app.profiles (user_id) on delete cascade,
  constraint home_player_uploads_media_asset_id_fkey
    foreign key (media_asset_id) references app.media_assets (id)
);

create index idx_home_player_uploads_media_asset
  on app.home_player_uploads (media_asset_id);

create index idx_home_player_uploads_teacher_created
  on app.home_player_uploads (teacher_id, created_at desc);

grant select, insert, update, delete
on table app.home_player_uploads
to authenticated, service_role;

alter table app.home_player_uploads enable row level security;

drop policy if exists home_player_uploads_owner_select on app.home_player_uploads;
create policy home_player_uploads_owner_select
on app.home_player_uploads
for select
to authenticated
using (teacher_id = auth.uid());

drop policy if exists home_player_uploads_owner_insert on app.home_player_uploads;
create policy home_player_uploads_owner_insert
on app.home_player_uploads
for insert
to authenticated
with check (teacher_id = auth.uid());

drop policy if exists home_player_uploads_owner_update on app.home_player_uploads;
create policy home_player_uploads_owner_update
on app.home_player_uploads
for update
to authenticated
using (teacher_id = auth.uid())
with check (teacher_id = auth.uid());

drop policy if exists home_player_uploads_owner_delete on app.home_player_uploads;
create policy home_player_uploads_owner_delete
on app.home_player_uploads
for delete
to authenticated
using (teacher_id = auth.uid());
