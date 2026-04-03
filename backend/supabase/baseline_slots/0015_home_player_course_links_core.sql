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
      foreign key (created_by) references app.profiles (user_id) on delete set null;
  end if;
end $$;

alter table app.lessons
  add column if not exists is_test boolean not null default false,
  add column if not exists test_session_id uuid;

alter table app.lesson_media
  add column if not exists is_test boolean not null default false,
  add column if not exists test_session_id uuid;

create table app.home_player_course_links (
  id uuid not null default extensions.gen_random_uuid(),
  teacher_id uuid not null,
  lesson_media_id uuid,
  title text not null,
  course_title_snapshot text not null default ''::text,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint home_player_course_links_pkey primary key (id),
  constraint home_player_course_links_teacher_id_fkey
    foreign key (teacher_id) references app.profiles (user_id) on delete cascade,
  constraint home_player_course_links_lesson_media_id_fkey
    foreign key (lesson_media_id) references app.lesson_media (id) on delete set null,
  constraint home_player_course_links_teacher_id_lesson_media_id_key
    unique (teacher_id, lesson_media_id)
);

create index idx_home_player_course_links_teacher_created
  on app.home_player_course_links (teacher_id, created_at desc);

grant select, insert, update, delete
on table app.home_player_course_links
to authenticated, service_role;

alter table app.home_player_course_links enable row level security;

drop policy if exists home_player_course_links_owner_select on app.home_player_course_links;
create policy home_player_course_links_owner_select
on app.home_player_course_links
for select
to authenticated
using (teacher_id = auth.uid());

drop policy if exists home_player_course_links_owner_insert on app.home_player_course_links;
create policy home_player_course_links_owner_insert
on app.home_player_course_links
for insert
to authenticated
with check (teacher_id = auth.uid());

drop policy if exists home_player_course_links_owner_update on app.home_player_course_links;
create policy home_player_course_links_owner_update
on app.home_player_course_links
for update
to authenticated
using (teacher_id = auth.uid())
with check (teacher_id = auth.uid());

drop policy if exists home_player_course_links_owner_delete on app.home_player_course_links;
create policy home_player_course_links_owner_delete
on app.home_player_course_links
for delete
to authenticated
using (teacher_id = auth.uid());
