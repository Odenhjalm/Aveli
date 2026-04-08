-- Kurs-paket (bundles) för lärare med Stripe-koppling.
create table if not exists app.course_bundles (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references app.profiles(user_id) on delete cascade,
  title text not null,
  description text,
  stripe_product_id text,
  stripe_price_id text,
  price_amount_cents integer not null default 0,
  currency text not null default 'sek',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_course_bundles_teacher on app.course_bundles(teacher_id);
create index if not exists idx_course_bundles_active on app.course_bundles(is_active);

create table if not exists app.course_bundle_courses (
  bundle_id uuid not null references app.course_bundles(id) on delete cascade,
  course_id uuid not null references app.courses(id) on delete cascade,
  position integer not null default 0,
  primary key (bundle_id, course_id)
);
create index if not exists idx_course_bundle_courses_bundle on app.course_bundle_courses(bundle_id);

alter table app.course_bundles enable row level security;
alter table app.course_bundle_courses enable row level security;

-- Publik läsning av aktiva paket; ägare får full access.
drop policy if exists course_bundles_public_read on app.course_bundles;
create policy course_bundles_public_read on app.course_bundles
  for select
  using (is_active = true);

drop policy if exists course_bundles_owner_write on app.course_bundles;
create policy course_bundles_owner_write on app.course_bundles
  for all
  using (auth.uid() = teacher_id)
  with check (auth.uid() = teacher_id);

drop policy if exists course_bundle_courses_owner on app.course_bundle_courses;
create policy course_bundle_courses_owner on app.course_bundle_courses
  for all
  using (auth.uid() in (
    select teacher_id from app.course_bundles where id = bundle_id
  ))
  with check (auth.uid() in (
    select teacher_id from app.course_bundles where id = bundle_id
  ));
