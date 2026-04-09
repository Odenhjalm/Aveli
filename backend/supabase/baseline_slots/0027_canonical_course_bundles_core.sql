create table if not exists app.course_bundles (
  id uuid not null default gen_random_uuid(),
  teacher_id uuid not null,
  title text not null,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint course_bundles_pkey primary key (id),
  constraint course_bundles_teacher_id_fkey
    foreign key (teacher_id) references app.auth_subjects (user_id)
);

create index if not exists idx_course_bundles_teacher
  on app.course_bundles (teacher_id);

create table if not exists app.course_bundle_courses (
  bundle_id uuid not null,
  course_id uuid not null,
  position integer not null default 0,
  constraint course_bundle_courses_pkey primary key (bundle_id, course_id),
  constraint course_bundle_courses_position_check check (position >= 0),
  constraint course_bundle_courses_bundle_id_fkey
    foreign key (bundle_id) references app.course_bundles (id),
  constraint course_bundle_courses_course_id_fkey
    foreign key (course_id) references app.courses (id)
);

create index if not exists idx_course_bundle_courses_bundle_position
  on app.course_bundle_courses (bundle_id, position, course_id);

comment on table app.course_bundles is
  'Canonical bundle identity and ownership substrate only. Monetization fields are intentionally excluded.';

comment on table app.course_bundle_courses is
  'Canonical bundle composition substrate only. Pricing, sellability, and payment logic are intentionally excluded.';
