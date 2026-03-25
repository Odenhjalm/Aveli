-- 006_seminar_sessions.sql
-- Extends seminars with session + recording metadata.

begin;

do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'seminar_session_status'
      and n.nspname = 'app'
  ) then
    create type app.seminar_session_status as enum ('scheduled','live','ended','failed');
  end if;
end$$;

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
comment on table app.seminar_sessions is 'Individual LiveKit sessions spawned for seminars.';

drop trigger if exists trg_seminar_sessions_touch on app.seminar_sessions;
create trigger trg_seminar_sessions_touch
before update on app.seminar_sessions
for each row execute procedure app.set_updated_at();

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
comment on table app.seminar_recordings is 'Stored outputs from webinar/SFU sessions.';

drop trigger if exists trg_seminar_recordings_touch on app.seminar_recordings;
create trigger trg_seminar_recordings_touch
before update on app.seminar_recordings
for each row execute procedure app.set_updated_at();

alter table app.seminar_attendees
  add column if not exists invite_status text not null default 'pending',
  add column if not exists left_at timestamptz,
  add column if not exists livekit_identity text,
  add column if not exists livekit_participant_sid text,
  add column if not exists livekit_room text;

commit;
