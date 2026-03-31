create table app.course_public_content (
  course_id uuid not null,
  short_description text not null,
  constraint course_public_content_pkey primary key (course_id),
  constraint course_public_content_course_id_fkey
    foreign key (course_id) references app.courses (id)
      on delete cascade
);
