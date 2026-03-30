create table app.course_enrollments (
  id uuid not null,
  user_id uuid not null,
  course_id uuid not null,
  source app.course_enrollment_source not null,
  granted_at timestamptz not null,
  drip_started_at timestamptz not null,
  current_unlock_position integer not null,
  constraint course_enrollments_pkey primary key (id),
  constraint course_enrollments_user_id_course_id_key unique (user_id, course_id),
  constraint course_enrollments_current_unlock_position_check check (
    current_unlock_position >= 0
  ),
  constraint course_enrollments_course_id_fkey
    foreign key (course_id) references app.courses (id)
);
