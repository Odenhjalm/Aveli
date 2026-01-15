-- 0002_tables_core.sql
-- Core application tables, views, and config.

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
  created_at timestamptz not null default now()
);

create index if not exists idx_auth_events_user on app.auth_events(user_id);
create index if not exists idx_auth_events_created_at on app.auth_events(created_at desc);

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

commit;
