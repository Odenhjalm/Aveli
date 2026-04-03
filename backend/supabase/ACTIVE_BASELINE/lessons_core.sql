create table app.lessons (
  id uuid not null,
  course_id uuid not null,
  lesson_title text not null,
  position integer not null,
  constraint lessons_pkey primary key (id),
  constraint lessons_course_id_position_key unique (course_id, position),
  constraint lessons_position_check check (position >= 1),
  constraint lessons_course_id_fkey
    foreign key (course_id) references app.courses (id)
);
