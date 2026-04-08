create table if not exists app.media_assets (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references app.profiles(user_id) on delete set null,
  course_id uuid references app.courses(id) on delete set null,
  lesson_id uuid references app.lessons(id) on delete set null,
  media_type text not null check (media_type in ('audio')),
  ingest_format text not null,
  original_object_path text not null,
  original_content_type text,
  original_filename text,
  original_size_bytes bigint,
  storage_bucket text not null default 'course-media',
  streaming_object_path text,
  streaming_format text,
  duration_seconds integer,
  codec text,
  state text not null check (state in ('uploaded', 'processing', 'ready', 'failed')),
  error_message text,
  processing_attempts integer not null default 0,
  processing_locked_at timestamptz,
  next_retry_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_media_assets_state on app.media_assets(state);
create index if not exists idx_media_assets_lesson on app.media_assets(lesson_id);
create index if not exists idx_media_assets_course on app.media_assets(course_id);
create index if not exists idx_media_assets_next_retry on app.media_assets(next_retry_at);

alter table app.lesson_media
  add column if not exists media_asset_id uuid references app.media_assets(id) on delete set null;

alter table app.lesson_media
  drop constraint if exists lesson_media_path_or_object;

alter table app.lesson_media
  add constraint lesson_media_path_or_object check (
    media_id is not null or storage_path is not null or media_asset_id is not null
  );

create index if not exists idx_lesson_media_asset on app.lesson_media(media_asset_id);
