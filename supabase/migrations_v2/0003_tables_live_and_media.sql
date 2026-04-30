-- 0003_tables_live_and_media.sql
-- Media and live-session tables.

begin;

-- ---------------------------------------------------------------------------
-- Media objects
-- ---------------------------------------------------------------------------
create table if not exists app.media_objects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references app.profiles(user_id) on delete set null,
  storage_path text not null,
  storage_bucket text not null default 'lesson-media',
  content_type text,
  byte_size bigint not null default 0,
  checksum text,
  original_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(storage_path, storage_bucket)
);

create index if not exists idx_media_owner on app.media_objects(owner_id);

create table if not exists app.lesson_media (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references app.lessons(id) on delete cascade,
  kind text not null check (kind in ('video','audio','image','pdf','other')),
  media_id uuid references app.media_objects(id) on delete set null,
  storage_path text,
  storage_bucket text not null default 'lesson-media',
  duration_seconds integer,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  unique(lesson_id, position),
  constraint lesson_media_path_or_object check (
    media_id is not null or storage_path is not null
  )
);

create index if not exists idx_lesson_media_lesson on app.lesson_media(lesson_id);
create index if not exists idx_lesson_media_media on app.lesson_media(media_id);

alter table app.profiles
  add column if not exists avatar_media_id uuid references app.media_objects(id);

-- ---------------------------------------------------------------------------
-- Seminars / LiveKit
-- ---------------------------------------------------------------------------
create table if not exists app.seminars (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references app.profiles(user_id) on delete cascade,
  title text not null,
  description text,
  status app.seminar_status not null default 'draft',
  scheduled_at timestamptz,
  duration_minutes integer,
  livekit_room text,
  livekit_metadata jsonb,
  recording_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_seminars_host on app.seminars(host_id);
create index if not exists idx_seminars_status on app.seminars(status);
create index if not exists idx_seminars_scheduled_at on app.seminars(scheduled_at);

create table if not exists app.seminar_attendees (
  seminar_id uuid not null references app.seminars(id) on delete cascade,
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  role text not null default 'participant',
  joined_at timestamptz,
  invite_status text not null default 'pending',
  left_at timestamptz,
  livekit_identity text,
  livekit_participant_sid text,
  livekit_room text,
  created_at timestamptz not null default now(),
  primary key (seminar_id, user_id)
);

create table if not exists app.seminar_sessions (
  id uuid primary key default gen_random_uuid(),
  seminar_id uuid not null references app.seminars(id) on delete cascade,
  status app.seminar_session_status not null default 'scheduled',
  scheduled_at timestamptz,
  started_at timestamptz,
  ended_at timestamptz,
  livekit_room text,
  livekit_sid text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_seminar_sessions_seminar on app.seminar_sessions(seminar_id);

create table if not exists app.seminar_recordings (
  id uuid primary key default gen_random_uuid(),
  seminar_id uuid not null references app.seminars(id) on delete cascade,
  session_id uuid references app.seminar_sessions(id) on delete set null,
  asset_url text,
  status text not null default 'processing',
  duration_seconds integer,
  byte_size bigint,
  published boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_seminar_recordings_seminar on app.seminar_recordings(seminar_id);

create table if not exists app.livekit_webhook_jobs (
  id uuid primary key default gen_random_uuid(),
  event text not null,
  payload jsonb not null,
  status text not null default 'pending',
  attempt integer not null default 0,
  last_error text,
  scheduled_at timestamptz not null default now(),
  locked_at timestamptz,
  last_attempt_at timestamptz,
  next_run_at timestamptz default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_livekit_webhook_jobs_status
  on app.livekit_webhook_jobs(status, scheduled_at);

commit;
