-- 0004_tables_marketplace.sql
-- Marketplace, teacher, and community tables.

begin;

-- ---------------------------------------------------------------------------
-- Teachers & payouts
-- ---------------------------------------------------------------------------
create table if not exists app.teachers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references app.profiles(user_id) on delete cascade unique,
  stripe_connect_account_id text unique,
  payout_split_pct integer not null default 100 check (payout_split_pct between 0 and 100),
  onboarded_at timestamptz,
  charges_enabled boolean not null default false,
  payouts_enabled boolean not null default false,
  requirements_due jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_teachers_connect_account on app.teachers(stripe_connect_account_id);

create table if not exists app.teacher_payout_methods (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references app.profiles(user_id) on delete cascade,
  provider text not null,
  reference text not null,
  details jsonb not null default '{}'::jsonb,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(teacher_id, provider, reference)
);

create index if not exists idx_payout_methods_teacher on app.teacher_payout_methods(teacher_id);

create table if not exists app.teacher_permissions (
  profile_id uuid primary key references app.profiles(user_id) on delete cascade,
  can_edit_courses boolean not null default false,
  can_publish boolean not null default false,
  granted_by uuid references app.profiles(user_id),
  granted_at timestamptz not null default now()
);

create table if not exists app.teacher_directory (
  user_id uuid primary key references app.profiles(user_id) on delete cascade,
  headline text,
  specialties text[],
  rating numeric(3,2),
  created_at timestamptz not null default now()
);

create table if not exists app.teacher_approvals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  reviewer_id uuid references app.profiles(user_id),
  status text not null default 'pending',
  notes text,
  approved_by uuid references app.profiles(user_id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id)
);

create index if not exists idx_teacher_approvals_user on app.teacher_approvals(user_id);

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

-- ---------------------------------------------------------------------------
-- Bundles and certifications
-- ---------------------------------------------------------------------------
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

create index if not exists idx_course_bundle_courses_bundle
  on app.course_bundle_courses(bundle_id);

create table if not exists app.certificates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  course_id uuid references app.courses(id) on delete set null,
  title text,
  status text not null default 'pending',
  notes text,
  evidence_url text,
  issued_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_certificates_user on app.certificates(user_id);

create table if not exists app.reviews (
  id uuid primary key default gen_random_uuid(),
  course_id uuid references app.courses(id) on delete cascade,
  service_id uuid references app.services(id) on delete cascade,
  order_id uuid references app.orders(id) on delete set null,
  reviewer_id uuid not null references app.profiles(user_id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text,
  visibility app.review_visibility not null default 'public',
  created_at timestamptz not null default now()
);

create index if not exists idx_reviews_course on app.reviews(course_id);
create index if not exists idx_reviews_service on app.reviews(service_id);
create index if not exists idx_reviews_reviewer on app.reviews(reviewer_id);
create index if not exists idx_reviews_order on app.reviews(order_id);

drop view if exists app.service_reviews;
create or replace view app.service_reviews as
select
  r.id,
  r.service_id,
  r.order_id,
  r.reviewer_id,
  r.rating,
  r.comment,
  r.visibility,
  r.created_at
from app.reviews r
where r.service_id is not null;

create table if not exists app.meditations (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  teacher_id uuid references app.profiles(user_id) on delete cascade,
  media_id uuid references app.media_objects(id) on delete set null,
  audio_path text,
  duration_seconds integer,
  is_public boolean not null default false,
  created_by uuid references app.profiles(user_id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists app.tarot_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references app.profiles(user_id) on delete cascade,
  question text not null,
  status text not null default 'open',
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Community tables
-- ---------------------------------------------------------------------------
create table if not exists app.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references app.profiles(user_id) on delete cascade,
  content text not null,
  media_paths jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_posts_author on app.posts(author_id);

create table if not exists app.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_notifications_user on app.notifications(user_id);
create index if not exists idx_notifications_read on app.notifications(user_id, read_at);

create table if not exists app.follows (
  follower_id uuid not null references app.profiles(user_id) on delete cascade,
  followee_id uuid not null references app.profiles(user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id)
);

create table if not exists app.messages (
  id uuid primary key default gen_random_uuid(),
  channel text,
  sender_id uuid references app.profiles(user_id) on delete set null,
  recipient_id uuid references app.profiles(user_id) on delete set null,
  content text,
  created_at timestamptz not null default now()
);

create index if not exists idx_messages_recipient on app.messages(recipient_id);
create index if not exists idx_messages_channel on app.messages(channel);

commit;
