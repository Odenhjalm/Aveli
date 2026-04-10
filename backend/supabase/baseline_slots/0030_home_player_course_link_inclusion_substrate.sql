create table if not exists app.home_player_course_links (
  id uuid not null default gen_random_uuid(),
  teacher_id uuid not null,
  lesson_media_id uuid,
  title text not null,
  course_title_snapshot text not null default ''::text,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint home_player_course_links_pkey primary key (id),
  constraint home_player_course_links_teacher_lesson_media_key unique (teacher_id, lesson_media_id),
  constraint home_player_course_links_lesson_media_id_fkey
    foreign key (lesson_media_id) references app.lesson_media (id) on delete set null
);

comment on table app.home_player_course_links is
  'Canonical home-audio inclusion substrate for course-linked home audio only. Course ownership remains app.courses.teacher_id.';

comment on column app.home_player_course_links.teacher_id is
  'Stored mirror only for mounted runtime compatibility. Not authoritative and does not override app.courses.teacher_id.';
