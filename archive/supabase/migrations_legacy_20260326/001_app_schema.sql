-- 001_app_schema.sql
-- Baseline schema for the Wisdom by SoulWisdom backend.
-- Idempotent so it can be executed multiple times safely.

begin;

-- Core extensions that power UUID helpers and cryptographic hashing.
create extension if not exists pgcrypto;
create extension if not exists "uuid-ossp";

-- Schemas -------------------------------------------------------------------
create schema if not exists auth;
create schema if not exists app;

-- ---------------------------------------------------------------------------
-- Enumerated types (checked before creation to avoid duplicate errors)
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'profile_role'
      and n.nspname = 'app'
  ) then
    create type app.profile_role as enum ('student', 'teacher', 'admin');
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'user_role'
      and n.nspname = 'app'
  ) then
    create type app.user_role as enum ('user', 'professional', 'teacher');
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'order_status'
      and n.nspname = 'app'
  ) then
    create type app.order_status as enum (
      'pending',
      'requires_action',
      'processing',
      'paid',
      'canceled',
      'failed',
      'refunded'
    );
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'payment_status'
      and n.nspname = 'app'
  ) then
    create type app.payment_status as enum (
      'pending',
      'processing',
      'paid',
      'failed',
      'refunded'
    );
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'enrollment_source'
      and n.nspname = 'app'
  ) then
    create type app.enrollment_source as enum (
      'free_intro',
      'purchase',
      'membership',
      'grant'
    );
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'service_status'
      and n.nspname = 'app'
  ) then
    create type app.service_status as enum (
      'draft',
      'active',
      'paused',
      'archived'
    );
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'seminar_status'
      and n.nspname = 'app'
  ) then
    create type app.seminar_status as enum (
      'draft',
      'scheduled',
      'live',
      'ended',
      'canceled'
    );
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'activity_kind'
      and n.nspname = 'app'
  ) then
    create type app.activity_kind as enum (
      'profile_updated',
      'course_published',
      'lesson_published',
      'service_created',
      'order_paid',
      'seminar_scheduled',
      'room_created',
      'participant_joined',
      'participant_left'
    );
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'review_visibility'
      and n.nspname = 'app'
  ) then
    create type app.review_visibility as enum ('public', 'private');
  end if;
end$$;

-- ---------------------------------------------------------------------------
-- Utility function for keeping updated_at in sync.
-- ---------------------------------------------------------------------------
create or replace function app.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Profiles & People
-- ---------------------------------------------------------------------------
create table if not exists app.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  display_name text,
  role app.profile_role not null default 'student',
  role_v2 app.user_role not null default 'user',
  bio text,
  photo_url text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- RLS placeholder: enable row level security and add self-access + admin policies.
comment on table app.profiles is
  'RLS placeholder: allow owners + admins to read/write their profile rows when Supabase is enabled.';

-- ---------------------------------------------------------------------------
-- Courses, modules, lessons, media
-- ---------------------------------------------------------------------------
create table if not exists app.courses (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  description text,
  cover_url text,
  video_url text,
  branch text,
  is_free_intro boolean not null default false,
  price_cents integer not null default 0,
  currency text not null default 'sek',
  is_published boolean not null default false,
  created_by uuid references app.profiles(user_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_courses_created_by on app.courses(created_by);
comment on table app.courses is
  'RLS placeholder: course authors (created_by) + admins may manage records; public read for published courses.';

create table if not exists app.modules (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references app.courses(id) on delete cascade,
  title text not null,
  summary text,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(course_id, position)
);
create index if not exists idx_modules_course on app.modules(course_id);

create table if not exists app.lessons (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references app.modules(id) on delete cascade,
  title text not null,
  content_markdown text,
  video_url text,
  duration_seconds integer,
  is_intro boolean not null default false,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(module_id, position)
);
create index if not exists idx_lessons_module on app.lessons(module_id);
comment on table app.lessons is
  'RLS placeholder: restrict lesson access to course owners and enrolled users once RLS is enabled.';

create table if not exists app.media_objects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references app.profiles(user_id) on delete set null,
  storage_path text not null,
  storage_bucket text not null default 'lesson-media',
  content_type text,
  byte_size bigint not null default 0,
  checksum text,
  original_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(storage_path, storage_bucket)
);
create index if not exists idx_media_owner on app.media_objects(owner_id);

create table if not exists app.lesson_media (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references app.lessons(id) on delete cascade,
  kind text not null check (kind in ('video','audio','image','pdf','other')),
  media_id uuid references app.media_objects(id) on delete set null,
  storage_path text,
  storage_bucket text not null default 'lesson-media',
  duration_seconds integer,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  unique(lesson_id, position),
  constraint lesson_media_path_or_object check (
    media_id is not null or storage_path is not null
  )
);
create index if not exists idx_lesson_media_lesson on app.lesson_media(lesson_id);
create index if not exists idx_lesson_media_media on app.lesson_media(media_id);

alter table app.profiles
  add column if not exists avatar_media_id uuid references app.media_objects(id);

-- ---------------------------------------------------------------------------
-- Enrollments & progress
-- ---------------------------------------------------------------------------
create table if not exists app.enrollments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  course_id uuid not null references app.courses(id) on delete cascade,
  status text not null default 'active',
  source app.enrollment_source not null default 'purchase',
  created_at timestamptz not null default now(),
  unique(user_id, course_id)
);
create index if not exists idx_enrollments_user on app.enrollments(user_id);
create index if not exists idx_enrollments_course on app.enrollments(course_id);
comment on table app.enrollments is
  'RLS placeholder: user_id rows visible to the learner, course owners, and admins.';

-- ---------------------------------------------------------------------------
-- Services marketplace
-- ---------------------------------------------------------------------------
create table if not exists app.services (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references app.profiles(user_id) on delete cascade,
  title text not null,
  description text,
  status app.service_status not null default 'draft',
  price_cents integer not null default 0,
  currency text not null default 'sek',
  duration_min integer,
  requires_certification boolean not null default false,
  certified_area text,
  thumbnail_url text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_services_provider on app.services(provider_id);
create index if not exists idx_services_status on app.services(status);
comment on table app.services is
  'RLS placeholder: providers manage their own services; public read for active services; admins override.';

-- ---------------------------------------------------------------------------
-- Orders & payments (Stripe first)
-- ---------------------------------------------------------------------------
create table if not exists app.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  course_id uuid references app.courses(id) on delete set null,
  service_id uuid references app.services(id) on delete set null,
  amount_cents integer not null,
  currency text not null default 'sek',
  status app.order_status not null default 'pending',
  stripe_checkout_id text,
  stripe_payment_intent text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_orders_user on app.orders(user_id);
create index if not exists idx_orders_status on app.orders(status);
create index if not exists idx_orders_service on app.orders(service_id);
create index if not exists idx_orders_course on app.orders(course_id);
comment on table app.orders is
  'RLS placeholder: buyers can read their own orders; admins and service providers may need scoped access.';

create or replace view app.service_orders as
select
  o.id,
  o.user_id,
  buyer.display_name as buyer_display_name,
  buyer.email as buyer_email,
  o.service_id,
  s.title as service_title,
  s.description as service_description,
  s.duration_min as service_duration_min,
  s.requires_certification as service_requires_certification,
  s.certified_area as service_certified_area,
  s.provider_id,
  provider.display_name as provider_display_name,
  provider.email as provider_email,
  o.amount_cents,
  o.currency,
  o.status,
  o.stripe_checkout_id,
  o.stripe_payment_intent,
  o.metadata,
  o.created_at,
  o.updated_at
from app.orders o
join app.services s on s.id = o.service_id
left join app.profiles buyer on buyer.user_id = o.user_id
left join app.profiles provider on provider.user_id = s.provider_id
where o.service_id is not null;
comment on view app.service_orders is
  'Convenience view joining service orders with buyer/provider details. RLS placeholder: restrict by buyer/provider/admin roles.';

create table if not exists app.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references app.orders(id) on delete cascade,
  provider text not null,
  provider_reference text,
  status app.payment_status not null default 'pending',
  amount_cents integer not null,
  currency text not null default 'sek',
  metadata jsonb not null default '{}'::jsonb,
  raw_payload jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_payments_order on app.payments(order_id);
create index if not exists idx_payments_status on app.payments(status);
comment on table app.payments is
  'RLS placeholder: restrict payment records to order owners and finance/admin roles.';

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

-- ---------------------------------------------------------------------------
-- Seminars / SFU foundation (LiveKit)
-- ---------------------------------------------------------------------------
create table if not exists app.seminars (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references app.profiles(user_id) on delete cascade,
  title text not null,
  description text,
  status app.seminar_status not null default 'draft',
  scheduled_at timestamptz,
  duration_minutes integer,
  livekit_room text,
  livekit_metadata jsonb,
  recording_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_seminars_host on app.seminars(host_id);
create index if not exists idx_seminars_status on app.seminars(status);
create index if not exists idx_seminars_scheduled_at on app.seminars(scheduled_at);
comment on table app.seminars is
  'RLS placeholder: allow public read of scheduled/live/ended seminars, host-owned writes, admin override.';

create table if not exists app.seminar_attendees (
  seminar_id uuid not null references app.seminars(id) on delete cascade,
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  role text not null default 'participant',
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (seminar_id, user_id)
);
comment on table app.seminar_attendees is
  'RLS placeholder: attendees may insert/delete themselves, host/admin manage all.';

create or replace function app.is_seminar_host(p_seminar_id uuid, p_user_id uuid)
returns boolean
language sql
as $$
  select exists(
    select 1
    from app.seminars s
    where s.id = p_seminar_id
      and s.host_id = p_user_id
  );
$$;

create or replace function app.is_seminar_attendee(p_seminar_id uuid, p_user_id uuid)
returns boolean
language sql
as $$
  select exists(
    select 1
    from app.seminar_attendees sa
    where sa.seminar_id = p_seminar_id
      and sa.user_id = p_user_id
  );
$$;

create or replace function app.can_access_seminar(p_seminar_id uuid, p_user_id uuid)
returns boolean
language sql
stable
as $$
  select
    app.is_seminar_host(p_seminar_id, p_user_id)
    or app.is_seminar_attendee(p_seminar_id, p_user_id);
$$;

-- ---------------------------------------------------------------------------
-- Activities feed
-- ---------------------------------------------------------------------------
create table if not exists app.activities (
  id uuid primary key default gen_random_uuid(),
  activity_type app.activity_kind not null,
  actor_id uuid references app.profiles(user_id) on delete set null,
  subject_table text not null,
  subject_id uuid,
  summary text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists idx_activities_type on app.activities(activity_type);
create index if not exists idx_activities_subject on app.activities(subject_table, subject_id);
create index if not exists idx_activities_occurred on app.activities(occurred_at desc);

create or replace view app.activities_feed as
select
  a.id,
  a.activity_type,
  a.actor_id,
  a.subject_table,
  a.subject_id,
  a.summary,
  a.metadata,
  a.occurred_at
from app.activities a;
-- RLS placeholder: convert to security barrier view with RLS-backed source tables.

-- ---------------------------------------------------------------------------
-- Authentication helpers (refresh tokens & audit)
-- ---------------------------------------------------------------------------
create table if not exists app.refresh_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  jti uuid not null unique,
  token_hash text not null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  rotated_at timestamptz,
  revoked_at timestamptz,
  last_used_at timestamptz
);
create index if not exists idx_refresh_tokens_user on app.refresh_tokens(user_id);

create table if not exists app.auth_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references app.profiles(user_id) on delete cascade,
  email text,
  event text not null,
  ip_address inet,
  user_agent text,
  metadata jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_auth_events_user on app.auth_events(user_id);
create index if not exists idx_auth_events_created_at on app.auth_events(created_at desc);

-- ---------------------------------------------------------------------------
-- Misc legacy-support tables referenced by the existing backend
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

create table if not exists app.app_config (
  id integer primary key default 1,
  platform_fee_pct numeric not null default 10
);

insert into app.app_config(id)
select 1
where not exists (select 1 from app.app_config where id = 1);

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

create table if not exists app.stripe_customers (
  user_id uuid primary key references app.profiles(user_id) on delete cascade,
  customer_id text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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

create table if not exists app.course_quizzes (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references app.courses(id) on delete cascade,
  title text,
  pass_score integer not null default 80,
  created_by uuid references app.profiles(user_id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists app.quiz_questions (
  id uuid primary key default gen_random_uuid(),
  course_id uuid references app.courses(id) on delete cascade,
  quiz_id uuid references app.course_quizzes(id) on delete cascade,
  position integer not null default 0,
  kind text not null default 'single',
  prompt text not null,
  options jsonb not null default '{}'::jsonb,
  correct text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_quiz_questions_course on app.quiz_questions(course_id);
create index if not exists idx_quiz_questions_quiz on app.quiz_questions(quiz_id);

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
comment on table app.reviews is
  'RLS placeholder: reviewers can manage their reviews; admins may moderate.';

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
comment on view app.service_reviews is
  'RLS placeholder: expose service-specific reviews; lock down via RLS once migrated to Supabase.';

-- ---------------------------------------------------------------------------
-- Touch triggers (ensure updated_at auto-refreshes)
-- ---------------------------------------------------------------------------
drop trigger if exists trg_courses_touch on app.courses;
create trigger trg_courses_touch
before update on app.courses
for each row
execute function app.set_updated_at();

drop trigger if exists trg_modules_touch on app.modules;
create trigger trg_modules_touch
before update on app.modules
for each row
execute function app.set_updated_at();

drop trigger if exists trg_lessons_touch on app.lessons;
create trigger trg_lessons_touch
before update on app.lessons
for each row
execute function app.set_updated_at();

drop trigger if exists trg_services_touch on app.services;
create trigger trg_services_touch
before update on app.services
for each row
execute function app.set_updated_at();

drop trigger if exists trg_orders_touch on app.orders;
create trigger trg_orders_touch
before update on app.orders
for each row
execute function app.set_updated_at();

drop trigger if exists trg_payments_touch on app.payments;
create trigger trg_payments_touch
before update on app.payments
for each row
execute function app.set_updated_at();

drop trigger if exists trg_seminars_touch on app.seminars;
create trigger trg_seminars_touch
before update on app.seminars
for each row
execute function app.set_updated_at();

drop trigger if exists trg_profiles_touch on app.profiles;
create trigger trg_profiles_touch
before update on app.profiles
for each row
execute function app.set_updated_at();

drop trigger if exists trg_teacher_approvals_touch on app.teacher_approvals;
create trigger trg_teacher_approvals_touch
before update on app.teacher_approvals
for each row
execute function app.set_updated_at();

drop trigger if exists trg_teacher_payout_methods_touch on app.teacher_payout_methods;
create trigger trg_teacher_payout_methods_touch
before update on app.teacher_payout_methods
for each row
execute function app.set_updated_at();

commit;
