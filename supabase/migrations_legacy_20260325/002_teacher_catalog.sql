-- 002_teacher_catalog.sql
-- Teacher course display ordering and curated profile media collections.

begin;

create table if not exists app.course_display_priorities (
  teacher_id uuid primary key references app.profiles(user_id) on delete cascade,
  priority integer not null default 1000,
  notes text,
  updated_by uuid references app.profiles(user_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_course_display_priorities_priority
  on app.course_display_priorities(priority);

comment on table app.course_display_priorities is
  'Controls teacher ordering in course listings and marketing blocks.';

create or replace function app.touch_course_display_priorities()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_course_display_priorities_touch on app.course_display_priorities;
create trigger trg_course_display_priorities_touch
before update on app.course_display_priorities
for each row execute procedure app.touch_course_display_priorities();

create table if not exists app.teacher_profile_media (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references app.profiles(user_id) on delete cascade,
  media_kind text not null check (media_kind in ('lesson_media','seminar_recording','external')),
  media_id uuid references app.lesson_media(id) on delete set null,
  external_url text,
  title text,
  description text,
  cover_media_id uuid references app.media_objects(id) on delete set null,
  cover_image_url text,
  position integer not null default 0,
  is_published boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(teacher_id, media_kind, media_id)
);

create index if not exists idx_teacher_profile_media_teacher
  on app.teacher_profile_media(teacher_id, position);

comment on table app.teacher_profile_media is
  'Curated media rows surfaced on teacher profile pages (lesson clips, seminar recordings, external links).';

create or replace function app.touch_teacher_profile_media()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_teacher_profile_media_touch on app.teacher_profile_media;
create trigger trg_teacher_profile_media_touch
before update on app.teacher_profile_media
for each row execute procedure app.touch_teacher_profile_media();

commit;
