-- 20260203153000_home_player_media_library.sql
-- Dedicated Home Player media library: Home uploads + course links.

begin;

create table if not exists app.home_player_uploads (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references app.profiles(user_id) on delete cascade,
  media_id uuid not null references app.media_objects(id),
  title text not null,
  kind text not null check (kind in ('audio', 'video')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_home_player_uploads_teacher_created
  on app.home_player_uploads(teacher_id, created_at desc);

create index if not exists idx_home_player_uploads_media
  on app.home_player_uploads(media_id);

comment on table app.home_player_uploads is
  'Teacher-owned uploads dedicated to the Home player (independent of courses).';

create or replace function app.touch_home_player_uploads()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_home_player_uploads_touch on app.home_player_uploads;
create trigger trg_home_player_uploads_touch
before update on app.home_player_uploads
for each row execute procedure app.touch_home_player_uploads();

create table if not exists app.home_player_course_links (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references app.profiles(user_id) on delete cascade,
  lesson_media_id uuid references app.lesson_media(id) on delete set null,
  title text not null,
  course_title_snapshot text not null default '',
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(teacher_id, lesson_media_id)
);

create index if not exists idx_home_player_course_links_teacher_created
  on app.home_player_course_links(teacher_id, created_at desc);

comment on table app.home_player_course_links is
  'Explicit course-media links for the Home player (no file ownership).';

create or replace function app.touch_home_player_course_links()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_home_player_course_links_touch on app.home_player_course_links;
create trigger trg_home_player_course_links_touch
before update on app.home_player_course_links
for each row execute procedure app.touch_home_player_course_links();

alter table app.home_player_uploads enable row level security;
alter table app.home_player_course_links enable row level security;

drop policy if exists home_player_uploads_owner on app.home_player_uploads;
create policy home_player_uploads_owner on app.home_player_uploads
  for all to authenticated
  using (teacher_id = auth.uid() or app.is_admin(auth.uid()))
  with check (teacher_id = auth.uid() or app.is_admin(auth.uid()));

drop policy if exists home_player_course_links_owner on app.home_player_course_links;
create policy home_player_course_links_owner on app.home_player_course_links
  for all to authenticated
  using (teacher_id = auth.uid() or app.is_admin(auth.uid()))
  with check (teacher_id = auth.uid() or app.is_admin(auth.uid()));

commit;

