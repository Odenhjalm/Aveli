create table app.lesson_contents (
  lesson_id uuid not null,
  content_markdown text not null,
  constraint lesson_contents_pkey primary key (lesson_id),
  constraint lesson_contents_lesson_id_fkey
    foreign key (lesson_id) references app.lessons (id)
);
