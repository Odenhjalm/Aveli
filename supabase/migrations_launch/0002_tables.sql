-- 0002_tables.sql
-- Core application tables and views for launch baseline.

begin;

-- ---------------------------------------------------------------------------
-- Profiles
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
  stripe_customer_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists profiles_stripe_customer_idx
  on app.profiles using btree ((lower(stripe_customer_id)));

-- ---------------------------------------------------------------------------
-- Courses, modules, lessons, quizzes
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
  price_amount_cents integer not null default 0,
  currency text not null default 'sek',
  is_published boolean not null default false,
  stripe_product_id text,
  stripe_price_id text,
  created_by uuid references app.profiles(user_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_courses_created_by on app.courses(created_by);
create index if not exists courses_slug_idx on app.courses(slug);

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

-- ---------------------------------------------------------------------------
-- Enrollments
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

-- ---------------------------------------------------------------------------
-- Services, sessions, orders, payments
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

create table if not exists app.sessions (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references app.profiles(user_id) on delete cascade,
  title text not null,
  description text,
  start_at timestamptz,
  end_at timestamptz,
  capacity integer check (capacity is null or capacity >= 0),
  price_cents integer not null default 0,
  currency text not null default 'sek',
  visibility app.session_visibility not null default 'draft',
  recording_url text,
  stripe_price_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_sessions_teacher on app.sessions(teacher_id);
create index if not exists idx_sessions_visibility on app.sessions(visibility);
create index if not exists idx_sessions_start_at on app.sessions(start_at);

create table if not exists app.session_slots (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references app.sessions(id) on delete cascade,
  start_at timestamptz not null,
  end_at timestamptz not null,
  seats_total integer not null default 1 check (seats_total >= 0),
  seats_taken integer not null default 0 check (seats_taken >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(session_id, start_at)
);

create index if not exists idx_session_slots_session on app.session_slots(session_id);
create index if not exists idx_session_slots_time on app.session_slots(start_at, end_at);

create table if not exists app.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  course_id uuid references app.courses(id) on delete set null,
  service_id uuid references app.services(id) on delete set null,
  session_id uuid references app.sessions(id) on delete set null,
  session_slot_id uuid references app.session_slots(id) on delete set null,
  order_type app.order_type not null default 'one_off',
  amount_cents integer not null,
  currency text not null default 'sek',
  status app.order_status not null default 'pending',
  stripe_checkout_id text,
  stripe_payment_intent text,
  stripe_subscription_id text,
  stripe_customer_id text,
  connected_account_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_orders_user on app.orders(user_id);
create index if not exists idx_orders_status on app.orders(status);
create index if not exists idx_orders_service on app.orders(service_id);
create index if not exists idx_orders_course on app.orders(course_id);
create index if not exists idx_orders_session on app.orders(session_id);
create index if not exists idx_orders_session_slot on app.orders(session_slot_id);
create index if not exists idx_orders_connected_account on app.orders(connected_account_id);

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

-- ---------------------------------------------------------------------------
-- Billing tables
-- ---------------------------------------------------------------------------
create table if not exists app.memberships (
  membership_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_interval text not null check (plan_interval in ('month','year')),
  price_id text not null,
  stripe_customer_id text,
  stripe_subscription_id text,
  start_date timestamptz not null default now(),
  end_date timestamptz,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id)
);

create table if not exists app.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  subscription_id text not null unique,
  status text not null default 'active',
  customer_id text,
  price_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_subscriptions_user on app.subscriptions(user_id);

create table if not exists app.payment_events (
  id uuid primary key default gen_random_uuid(),
  event_id text unique not null,
  payload jsonb not null,
  processed_at timestamptz default now()
);

create table if not exists app.billing_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  step text,
  info jsonb,
  created_at timestamptz default now()
);

-- ---------------------------------------------------------------------------
-- Entitlements & purchases
-- ---------------------------------------------------------------------------
create table if not exists app.course_entitlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  course_slug text not null,
  stripe_customer_id text,
  stripe_payment_intent_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, course_slug)
);

create index if not exists idx_course_entitlements_user_course
  on app.course_entitlements (user_id, course_slug);

create table if not exists app.course_products (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references app.courses(id) on delete cascade,
  stripe_product_id text not null,
  stripe_price_id text not null,
  price_amount integer not null,
  price_currency text not null default 'sek',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (course_id)
);

create index if not exists idx_course_products_course
  on app.course_products (course_id);

create table if not exists app.entitlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  course_id uuid not null references app.courses(id) on delete cascade,
  source text not null,
  stripe_session_id text,
  created_at timestamptz not null default now()
);

create index if not exists idx_entitlements_user on app.entitlements (user_id);
create index if not exists idx_entitlements_course on app.entitlements (course_id);
create index if not exists idx_entitlements_user_course
  on app.entitlements (user_id, course_id);

create table if not exists app.purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  order_id uuid references app.orders(id) on delete set null,
  stripe_payment_intent text,
  created_at timestamptz not null default now()
);

create index if not exists idx_purchases_user on app.purchases (user_id);
create index if not exists idx_purchases_order on app.purchases (order_id);

create table if not exists app.guest_claim_tokens (
  id uuid primary key default gen_random_uuid(),
  token text not null,
  purchase_id uuid references app.purchases(id) on delete cascade,
  course_id uuid references app.courses(id) on delete set null,
  used boolean not null default false,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create unique index if not exists guest_claim_tokens_token_key
  on app.guest_claim_tokens (token);
create index if not exists idx_guest_claim_tokens_expires
  on app.guest_claim_tokens (expires_at);
create index if not exists idx_guest_claim_tokens_used
  on app.guest_claim_tokens (used);

-- ---------------------------------------------------------------------------
-- Auth-adjacent tables
-- ---------------------------------------------------------------------------
create table if not exists app.stripe_customers (
  user_id uuid primary key references app.profiles(user_id) on delete cascade,
  customer_id text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists idx_auth_events_user on app.auth_events(user_id);
create index if not exists idx_auth_events_created_at on app.auth_events(created_at desc);
create index if not exists idx_auth_events_occurred_at on app.auth_events(occurred_at desc);

-- ---------------------------------------------------------------------------
-- Misc
-- ---------------------------------------------------------------------------
create table if not exists app.app_config (
  id integer primary key default 1,
  free_course_limit integer not null default 5,
  platform_fee_pct numeric not null default 10
);

insert into app.app_config(id)
select 1
where not exists (select 1 from app.app_config where id = 1);

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

-- ---------------------------------------------------------------------------
-- Media objects
-- ---------------------------------------------------------------------------
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
-- Seminars / LiveKit
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

create table if not exists app.seminar_attendees (
  seminar_id uuid not null references app.seminars(id) on delete cascade,
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  role text not null default 'participant',
  joined_at timestamptz,
  invite_status text not null default 'pending',
  left_at timestamptz,
  livekit_identity text,
  livekit_participant_sid text,
  livekit_room text,
  created_at timestamptz not null default now(),
  primary key (seminar_id, user_id)
);

create table if not exists app.seminar_sessions (
  id uuid primary key default gen_random_uuid(),
  seminar_id uuid not null references app.seminars(id) on delete cascade,
  status app.seminar_session_status not null default 'scheduled',
  scheduled_at timestamptz,
  started_at timestamptz,
  ended_at timestamptz,
  livekit_room text,
  livekit_sid text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_seminar_sessions_seminar on app.seminar_sessions(seminar_id);

create table if not exists app.seminar_recordings (
  id uuid primary key default gen_random_uuid(),
  seminar_id uuid not null references app.seminars(id) on delete cascade,
  session_id uuid references app.seminar_sessions(id) on delete set null,
  asset_url text,
  status text not null default 'processing',
  duration_seconds integer,
  byte_size bigint,
  published boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_seminar_recordings_seminar on app.seminar_recordings(seminar_id);

create table if not exists app.livekit_webhook_jobs (
  id uuid primary key default gen_random_uuid(),
  event text not null,
  payload jsonb not null,
  status text not null default 'pending',
  attempt integer not null default 0,
  last_error text,
  scheduled_at timestamptz not null default now(),
  locked_at timestamptz,
  last_attempt_at timestamptz,
  next_run_at timestamptz default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_livekit_webhook_jobs_status
  on app.livekit_webhook_jobs(status, scheduled_at);

-- ---------------------------------------------------------------------------
-- Teachers & marketplace
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
  reader_id uuid,
  question text not null,
  status text not null default 'open',
  deliverable_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
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
  kind text not null,
  payload jsonb not null default '{}'::jsonb,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_notifications_user on app.notifications(user_id);
create index if not exists idx_notifications_read on app.notifications(user_id, is_read);

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

-- ---------------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------------
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

commit;
