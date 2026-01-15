-- 0003_tables_extended.sql
-- Remote/extended tables that are not part of the core chain.

-- Live events --------------------------------------------------------------
create table if not exists app.live_events (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references app.profiles(user_id) on delete cascade,
  course_id uuid references app.courses(id) on delete set null,
  title text not null,
  description text,
  access_type text not null default 'course',
  starts_at timestamptz,
  ends_at timestamptz,
  status text not null default 'scheduled',
  capacity integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_live_events_teacher on app.live_events(teacher_id);
create index if not exists idx_live_events_course on app.live_events(course_id);
create index if not exists idx_live_events_status on app.live_events(status);

create table if not exists app.live_event_registrations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references app.live_events(id) on delete cascade,
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  status text not null default 'registered',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, user_id)
);
create index if not exists idx_live_event_registrations_event
  on app.live_event_registrations(event_id);
create index if not exists idx_live_event_registrations_user
  on app.live_event_registrations(user_id);

-- Purchases / products / entitlements -------------------------------------
create table if not exists app.purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  order_id uuid references app.orders(id) on delete set null,
  stripe_payment_intent text,
  created_at timestamptz not null default now()
);
create index if not exists idx_purchases_user on app.purchases(user_id);
create index if not exists idx_purchases_order on app.purchases(order_id);

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
create index if not exists idx_course_products_course on app.course_products(course_id);

create table if not exists app.entitlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  course_id uuid not null references app.courses(id) on delete cascade,
  source text not null,
  stripe_session_id text,
  created_at timestamptz not null default now()
);
create index if not exists idx_entitlements_user on app.entitlements(user_id);
create index if not exists idx_entitlements_course on app.entitlements(course_id);
create index if not exists idx_entitlements_user_course on app.entitlements(user_id, course_id);

create table if not exists app.guest_claim_tokens (
  id uuid primary key default gen_random_uuid(),
  token text not null,
  purchase_id uuid references app.purchases(id) on delete cascade,
  course_id uuid references app.courses(id) on delete set null,
  used boolean not null default false,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (token)
);
create index if not exists idx_guest_claim_tokens_expires on app.guest_claim_tokens(expires_at);
create index if not exists idx_guest_claim_tokens_used on app.guest_claim_tokens(used);

-- Classroom tables ---------------------------------------------------------
create table if not exists app.classroom_messages (
  id uuid primary key default gen_random_uuid(),
  classroom_id uuid not null,
  course_id uuid references app.courses(id) on delete set null,
  sender_id uuid references app.profiles(user_id) on delete set null,
  content text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_classroom_messages_classroom
  on app.classroom_messages(classroom_id);
create index if not exists idx_classroom_messages_sender
  on app.classroom_messages(sender_id);

create table if not exists app.classroom_presence (
  id uuid primary key default gen_random_uuid(),
  classroom_id uuid not null,
  user_id uuid not null references app.profiles(user_id) on delete cascade,
  status text not null default 'active',
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (classroom_id, user_id)
);
create index if not exists idx_classroom_presence_classroom
  on app.classroom_presence(classroom_id);
create index if not exists idx_classroom_presence_user
  on app.classroom_presence(user_id);

-- Lesson packages ----------------------------------------------------------
create table if not exists app.lesson_packages (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references app.courses(id) on delete cascade,
  title text not null,
  description text,
  price_amount_cents integer not null default 0,
  price_currency text not null default 'sek',
  stripe_product_id text,
  stripe_price_id text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_lesson_packages_course on app.lesson_packages(course_id);
create index if not exists idx_lesson_packages_active on app.lesson_packages(is_active);

-- Teacher accounts ---------------------------------------------------------
create table if not exists app.teacher_accounts (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references app.profiles(user_id) on delete cascade,
  stripe_account_id text,
  charges_enabled boolean not null default false,
  payouts_enabled boolean not null default false,
  details_submitted boolean not null default false,
  status text not null default 'pending',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (profile_id)
);
create index if not exists idx_teacher_accounts_stripe on app.teacher_accounts(stripe_account_id);

-- Welcome cards ------------------------------------------------------------
create table if not exists app.welcome_cards (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text,
  image_url text,
  cta_url text,
  is_active boolean not null default true,
  position integer not null default 0,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_welcome_cards_active on app.welcome_cards(is_active);
create index if not exists idx_welcome_cards_position on app.welcome_cards(position);

-- Music tracks -------------------------------------------------------------
create table if not exists app.music_tracks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  artist text,
  album text,
  storage_path text not null,
  storage_bucket text not null default 'audio_private',
  duration_seconds integer,
  is_public boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_music_tracks_public on app.music_tracks(is_public);
create index if not exists idx_music_tracks_bucket on app.music_tracks(storage_bucket);
