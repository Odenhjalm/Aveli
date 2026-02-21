# Launch DB Structure Contract

## Scope
This contract defines the canonical Supabase Postgres schema for launch.
It is derived from backend SQL usage (highest priority), Flutter API usage (endpoint and response keys),
and repository migrations (legacy + v2 attempts). Remote drift is not authoritative.

If a required column or type cannot be inferred from code or migrations, it is marked as TODO.

## Schemas
- auth (managed by Supabase; referenced for auth.users)
- app (all application tables and functions)

## Enumerated Types (app)
- profile_role: enum('student','teacher','admin')
- user_role: enum('user','professional','teacher')
- order_status: enum('pending','requires_action','processing','paid','canceled','failed','refunded')
- payment_status: enum('pending','processing','paid','failed','refunded')
- enrollment_source: enum('free_intro','purchase','membership','grant')
- service_status: enum('draft','active','paused','archived')
- seminar_status: enum('draft','scheduled','live','ended','canceled')
- activity_kind: enum('profile_updated','course_published','lesson_published','service_created','order_paid','seminar_scheduled','room_created','participant_joined','participant_left')
- review_visibility: enum('public','private')
- session_visibility: enum('draft','published')
- order_type: enum('one_off','subscription','bundle')
- seminar_session_status: enum('scheduled','live','ended','failed')

## Tables (app)

### app.profiles
Columns:
- user_id uuid PK FK auth.users(id) on delete cascade
- email text not null unique
- display_name text
- role app.profile_role not null default 'student'
- role_v2 app.user_role not null default 'user'
- bio text
- photo_url text
- is_admin boolean not null default false
- stripe_customer_id text
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
- avatar_media_id uuid FK app.media_objects(id) on delete set null
Indexes:
- profiles_stripe_customer_idx on lower(stripe_customer_id)

### app.courses
Columns:
- id uuid PK default gen_random_uuid()
- slug text not null unique
- title text not null
- description text
- cover_url text
- video_url text
- branch text
- is_free_intro boolean not null default false
- price_cents integer not null default 0
- price_amount_cents integer not null default 0
- currency text not null default 'sek'
- is_published boolean not null default false
- stripe_product_id text
- stripe_price_id text
- created_by uuid FK app.profiles(user_id) on delete set null
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_courses_created_by on created_by
- courses_slug_idx on slug

### app.modules
Columns:
- id uuid PK default gen_random_uuid()
- course_id uuid not null FK app.courses(id) on delete cascade
- title text not null
- summary text
- position integer not null default 0
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Constraints:
- unique(course_id, position)
Indexes:
- idx_modules_course on course_id

### app.lessons
Columns:
- id uuid PK default gen_random_uuid()
- module_id uuid not null FK app.modules(id) on delete cascade
- title text not null
- content_markdown text
- video_url text
- duration_seconds integer
- is_intro boolean not null default false
- position integer not null default 0
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Constraints:
- unique(module_id, position)
Indexes:
- idx_lessons_module on module_id

### app.course_quizzes
Columns:
- id uuid PK default gen_random_uuid()
- course_id uuid not null FK app.courses(id) on delete cascade
- title text
- pass_score integer not null default 80
- created_by uuid FK app.profiles(user_id) on delete set null
- created_at timestamptz not null default now()

### app.quiz_questions
Columns:
- id uuid PK default gen_random_uuid()
- course_id uuid FK app.courses(id) on delete cascade
- quiz_id uuid FK app.course_quizzes(id) on delete cascade
- position integer not null default 0
- kind text not null default 'single'
- prompt text not null
- options jsonb not null default '{}'::jsonb
- correct text
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_quiz_questions_course on course_id
- idx_quiz_questions_quiz on quiz_id

### app.enrollments
Columns:
- id uuid PK default gen_random_uuid()
- user_id uuid not null FK app.profiles(user_id) on delete cascade
- course_id uuid not null FK app.courses(id) on delete cascade
- status text not null default 'active'
- source app.enrollment_source not null default 'purchase'
- created_at timestamptz not null default now()
Constraints:
- unique(user_id, course_id)
Indexes:
- idx_enrollments_user on user_id
- idx_enrollments_course on course_id

### app.services
Columns:
- id uuid PK default gen_random_uuid()
- provider_id uuid not null FK app.profiles(user_id) on delete cascade
- title text not null
- description text
- status app.service_status not null default 'draft'
- price_cents integer not null default 0
- currency text not null default 'sek'
- duration_min integer
- requires_certification boolean not null default false
- certified_area text
- thumbnail_url text
- active boolean not null default true
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_services_provider on provider_id
- idx_services_status on status

### app.sessions
Columns:
- id uuid PK default gen_random_uuid()
- teacher_id uuid not null FK app.profiles(user_id) on delete cascade
- title text not null
- description text
- start_at timestamptz
- end_at timestamptz
- capacity integer check (capacity is null or capacity >= 0)
- price_cents integer not null default 0
- currency text not null default 'sek'
- visibility app.session_visibility not null default 'draft'
- recording_url text
- stripe_price_id text
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_sessions_teacher on teacher_id
- idx_sessions_visibility on visibility
- idx_sessions_start_at on start_at

### app.session_slots
Columns:
- id uuid PK default gen_random_uuid()
- session_id uuid not null FK app.sessions(id) on delete cascade
- start_at timestamptz not null
- end_at timestamptz not null
- seats_total integer not null default 1 check (seats_total >= 0)
- seats_taken integer not null default 0 check (seats_taken >= 0)
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Constraints:
- unique(session_id, start_at)
Indexes:
- idx_session_slots_session on session_id
- idx_session_slots_time on (start_at, end_at)

### app.orders
Columns:
- id uuid PK default gen_random_uuid()
- user_id uuid not null FK app.profiles(user_id) on delete cascade
- course_id uuid FK app.courses(id) on delete set null
- service_id uuid FK app.services(id) on delete set null
- session_id uuid FK app.sessions(id) on delete set null
- session_slot_id uuid FK app.session_slots(id) on delete set null
- order_type app.order_type not null default 'one_off'
- amount_cents integer not null
- currency text not null default 'sek'
- status app.order_status not null default 'pending'
- stripe_checkout_id text
- stripe_payment_intent text
- stripe_subscription_id text
- stripe_customer_id text
- connected_account_id text
- metadata jsonb not null default '{}'::jsonb
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_orders_user on user_id
- idx_orders_status on status
- idx_orders_service on service_id
- idx_orders_course on course_id
- idx_orders_session on session_id
- idx_orders_session_slot on session_slot_id
- idx_orders_connected_account on connected_account_id

### app.payments
Columns:
- id uuid PK default gen_random_uuid()
- order_id uuid not null FK app.orders(id) on delete cascade
- provider text not null
- provider_reference text
- status app.payment_status not null default 'pending'
- amount_cents integer not null
- currency text not null default 'sek'
- metadata jsonb not null default '{}'::jsonb
- raw_payload jsonb
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_payments_order on order_id
- idx_payments_status on status

### app.memberships
Columns:
- membership_id uuid PK default gen_random_uuid()
- user_id uuid not null FK auth.users(id) on delete cascade
- plan_interval text not null check (plan_interval in ('month','year'))
- price_id text not null
- stripe_customer_id text
- stripe_subscription_id text
- start_date timestamptz not null default now()
- end_date timestamptz
- status text not null default 'active'
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Constraints:
- unique(user_id)

### app.subscriptions
Columns:
- id uuid PK default gen_random_uuid()
- user_id uuid not null FK app.profiles(user_id) on delete cascade
- subscription_id text not null unique
- status text not null default 'active'
- customer_id text
- price_id text
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_subscriptions_user on user_id

### app.payment_events
Columns:
- id uuid PK default gen_random_uuid()
- event_id text not null unique
- payload jsonb not null
- processed_at timestamptz default now()

### app.billing_logs
Columns:
- id uuid PK default gen_random_uuid()
- user_id uuid
- step text
- info jsonb
- created_at timestamptz default now()

### app.course_entitlements
Columns:
- id uuid PK default gen_random_uuid()
- user_id uuid not null FK auth.users(id) on delete cascade
- course_slug text not null
- stripe_customer_id text
- stripe_payment_intent_id text
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Constraints:
- unique(user_id, course_slug)
Indexes:
- idx_course_entitlements_user_course on (user_id, course_slug)

### app.course_products
Columns:
- id uuid PK default gen_random_uuid()
- course_id uuid not null FK app.courses(id) on delete cascade
- stripe_product_id text not null
- stripe_price_id text not null
- price_amount integer not null
- price_currency text not null default 'sek'
- is_active boolean not null default true
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Constraints:
- unique(course_id)
Indexes:
- idx_course_products_course on course_id

### app.entitlements
Columns:
- id uuid PK default gen_random_uuid()
- user_id uuid not null FK app.profiles(user_id) on delete cascade
- course_id uuid not null FK app.courses(id) on delete cascade
- source text not null
- stripe_session_id text
- created_at timestamptz not null default now()
Indexes:
- idx_entitlements_user on user_id
- idx_entitlements_course on course_id
- idx_entitlements_user_course on (user_id, course_id)

### app.purchases
Columns:
- id uuid PK default gen_random_uuid()
- user_id uuid not null FK app.profiles(user_id) on delete cascade
- order_id uuid FK app.orders(id) on delete set null
- stripe_payment_intent text
- created_at timestamptz not null default now()
Indexes:
- idx_purchases_user on user_id
- idx_purchases_order on order_id

### app.guest_claim_tokens
Columns:
- id uuid PK default gen_random_uuid()
- token text not null
- purchase_id uuid FK app.purchases(id) on delete cascade
- course_id uuid FK app.courses(id) on delete set null
- used boolean not null default false
- expires_at timestamptz not null
- created_at timestamptz not null default now()
Indexes:
- guest_claim_tokens_token_key unique on token
- idx_guest_claim_tokens_expires on expires_at
- idx_guest_claim_tokens_used on used

### app.stripe_customers
Columns:
- user_id uuid PK FK app.profiles(user_id) on delete cascade
- customer_id text not null
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()

### app.refresh_tokens
Columns:
- id uuid PK default gen_random_uuid()
- user_id uuid not null FK app.profiles(user_id) on delete cascade
- jti uuid not null unique
- token_hash text not null
- issued_at timestamptz not null default now()
- expires_at timestamptz not null
- rotated_at timestamptz
- revoked_at timestamptz
- last_used_at timestamptz
Indexes:
- idx_refresh_tokens_user on user_id

### app.auth_events
Columns:
- id uuid PK default gen_random_uuid()
- user_id uuid FK app.profiles(user_id) on delete cascade
- email text
- event text not null
- ip_address inet
- user_agent text
- metadata jsonb
- occurred_at timestamptz not null default now()
- created_at timestamptz not null default now()
Indexes:
- idx_auth_events_user on user_id
- idx_auth_events_created_at on created_at desc
- idx_auth_events_occurred_at on occurred_at desc

### app.app_config
Columns:
- id integer PK default 1
- free_course_limit integer not null default 5
- platform_fee_pct numeric not null default 10
Seed:
- insert row id=1 if missing

### app.activities
Columns:
- id uuid PK default gen_random_uuid()
- activity_type app.activity_kind not null
- actor_id uuid FK app.profiles(user_id) on delete set null
- subject_table text not null
- subject_id uuid
- summary text
- metadata jsonb not null default '{}'::jsonb
- occurred_at timestamptz not null default now()
- created_at timestamptz not null default now()
Indexes:
- idx_activities_type on activity_type
- idx_activities_subject on (subject_table, subject_id)
- idx_activities_occurred on occurred_at desc

### app.media_objects
Columns:
- id uuid PK default gen_random_uuid()
- owner_id uuid FK app.profiles(user_id) on delete set null
- storage_path text not null
- storage_bucket text not null default 'lesson-media'
- content_type text
- byte_size bigint not null default 0
- checksum text
- original_name text
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Constraints:
- unique(storage_path, storage_bucket)
Indexes:
- idx_media_owner on owner_id

### app.lesson_media
Columns:
- id uuid PK default gen_random_uuid()
- lesson_id uuid not null FK app.lessons(id) on delete cascade
- kind text not null check (kind in ('video','audio','image','pdf','other'))
- media_id uuid FK app.media_objects(id) on delete set null
- storage_path text
- storage_bucket text not null default 'lesson-media'
- duration_seconds integer
- position integer not null default 0
- created_at timestamptz not null default now()
Constraints:
- unique(lesson_id, position)
- lesson_media_path_or_object check (media_id is not null or storage_path is not null)
Indexes:
- idx_lesson_media_lesson on lesson_id
- idx_lesson_media_media on media_id

### app.seminars
Columns:
- id uuid PK default gen_random_uuid()
- host_id uuid not null FK app.profiles(user_id) on delete cascade
- title text not null
- description text
- status app.seminar_status not null default 'draft'
- scheduled_at timestamptz
- duration_minutes integer
- livekit_room text
- livekit_metadata jsonb
- recording_url text
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_seminars_host on host_id
- idx_seminars_status on status
- idx_seminars_scheduled_at on scheduled_at

### app.seminar_attendees
Columns:
- seminar_id uuid not null FK app.seminars(id) on delete cascade
- user_id uuid not null FK app.profiles(user_id) on delete cascade
- role text not null default 'participant'
- joined_at timestamptz
- invite_status text not null default 'pending'
- left_at timestamptz
- livekit_identity text
- livekit_participant_sid text
- livekit_room text
- created_at timestamptz not null default now()
Constraints:
- primary key (seminar_id, user_id)

### app.seminar_sessions
Columns:
- id uuid PK default gen_random_uuid()
- seminar_id uuid not null FK app.seminars(id) on delete cascade
- status app.seminar_session_status not null default 'scheduled'
- scheduled_at timestamptz
- started_at timestamptz
- ended_at timestamptz
- livekit_room text
- livekit_sid text
- metadata jsonb not null default '{}'::jsonb
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_seminar_sessions_seminar on seminar_id

### app.seminar_recordings
Columns:
- id uuid PK default gen_random_uuid()
- seminar_id uuid not null FK app.seminars(id) on delete cascade
- session_id uuid FK app.seminar_sessions(id) on delete set null
- asset_url text
- status text not null default 'processing'
- duration_seconds integer
- byte_size bigint
- published boolean not null default false
- metadata jsonb not null default '{}'::jsonb
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_seminar_recordings_seminar on seminar_id

### app.livekit_webhook_jobs
Columns:
- id uuid PK default gen_random_uuid()
- event text not null
- payload jsonb not null
- status text not null default 'pending'
- attempt integer not null default 0
- last_error text
- scheduled_at timestamptz not null default now()
- locked_at timestamptz
- last_attempt_at timestamptz
- next_run_at timestamptz default now()
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_livekit_webhook_jobs_status on (status, scheduled_at)

### app.teachers
Columns:
- id uuid PK default gen_random_uuid()
- profile_id uuid not null unique FK app.profiles(user_id) on delete cascade
- stripe_connect_account_id text unique
- payout_split_pct integer not null default 100 check (payout_split_pct between 0 and 100)
- onboarded_at timestamptz
- charges_enabled boolean not null default false
- payouts_enabled boolean not null default false
- requirements_due jsonb not null default '{}'::jsonb
- status text not null default 'pending'
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_teachers_connect_account on stripe_connect_account_id

### app.teacher_payout_methods
Columns:
- id uuid PK default gen_random_uuid()
- teacher_id uuid not null FK app.profiles(user_id) on delete cascade
- provider text not null
- reference text not null
- details jsonb not null default '{}'::jsonb
- is_default boolean not null default false
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Constraints:
- unique(teacher_id, provider, reference)
Indexes:
- idx_payout_methods_teacher on teacher_id

### app.teacher_permissions
Columns:
- profile_id uuid PK FK app.profiles(user_id) on delete cascade
- can_edit_courses boolean not null default false
- can_publish boolean not null default false
- granted_by uuid FK app.profiles(user_id)
- granted_at timestamptz not null default now()

### app.teacher_directory
Columns:
- user_id uuid PK FK app.profiles(user_id) on delete cascade
- headline text
- specialties text[]
- rating numeric(3,2)
- created_at timestamptz not null default now()

### app.teacher_approvals
Columns:
- id uuid PK default gen_random_uuid()
- user_id uuid not null unique FK app.profiles(user_id) on delete cascade
- reviewer_id uuid FK app.profiles(user_id)
- status text not null default 'pending'
- notes text
- approved_by uuid FK app.profiles(user_id)
- approved_at timestamptz
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_teacher_approvals_user on user_id

### app.course_display_priorities
Columns:
- teacher_id uuid PK FK app.profiles(user_id) on delete cascade
- priority integer not null default 1000
- notes text
- updated_by uuid FK app.profiles(user_id) on delete set null
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_course_display_priorities_priority on priority

### app.teacher_profile_media
Columns:
- id uuid PK default gen_random_uuid()
- teacher_id uuid not null FK app.profiles(user_id) on delete cascade
- media_kind text not null check (media_kind in ('lesson_media','seminar_recording','external'))
- media_id uuid FK app.lesson_media(id) on delete set null
- external_url text
- title text
- description text
- cover_media_id uuid FK app.media_objects(id) on delete set null
- cover_image_url text
- position integer not null default 0
- is_published boolean not null default true
- metadata jsonb not null default '{}'::jsonb
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Constraints:
- unique(teacher_id, media_kind, media_id)
Indexes:
- idx_teacher_profile_media_teacher on (teacher_id, position)

### app.course_bundles
Columns:
- id uuid PK default gen_random_uuid()
- teacher_id uuid not null FK app.profiles(user_id) on delete cascade
- title text not null
- description text
- stripe_product_id text
- stripe_price_id text
- price_amount_cents integer not null default 0
- currency text not null default 'sek'
- is_active boolean not null default true
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_course_bundles_teacher on teacher_id
- idx_course_bundles_active on is_active

### app.course_bundle_courses
Columns:
- bundle_id uuid not null FK app.course_bundles(id) on delete cascade
- course_id uuid not null FK app.courses(id) on delete cascade
- position integer not null default 0
Constraints:
- primary key (bundle_id, course_id)
Indexes:
- idx_course_bundle_courses_bundle on bundle_id

### app.certificates
Columns:
- id uuid PK default gen_random_uuid()
- user_id uuid not null FK app.profiles(user_id) on delete cascade
- course_id uuid FK app.courses(id) on delete set null
- title text
- status text not null default 'pending'
- notes text
- evidence_url text
- issued_at timestamptz
- metadata jsonb not null default '{}'::jsonb
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Indexes:
- idx_certificates_user on user_id

### app.reviews
Columns:
- id uuid PK default gen_random_uuid()
- course_id uuid FK app.courses(id) on delete cascade
- service_id uuid FK app.services(id) on delete cascade
- order_id uuid FK app.orders(id) on delete set null
- reviewer_id uuid not null FK app.profiles(user_id) on delete cascade
- rating integer not null check (rating between 1 and 5)
- comment text
- visibility app.review_visibility not null default 'public'
- created_at timestamptz not null default now()
Indexes:
- idx_reviews_course on course_id
- idx_reviews_service on service_id
- idx_reviews_reviewer on reviewer_id
- idx_reviews_order on order_id

### app.meditations
Columns:
- id uuid PK default gen_random_uuid()
- title text not null
- description text
- teacher_id uuid FK app.profiles(user_id) on delete cascade
- media_id uuid FK app.media_objects(id) on delete set null
- audio_path text
- duration_seconds integer
- is_public boolean not null default false
- created_by uuid FK app.profiles(user_id) on delete set null
- created_at timestamptz not null default now()

### app.tarot_requests
Columns:
- id uuid PK default gen_random_uuid()
- requester_id uuid not null FK app.profiles(user_id) on delete cascade
- reader_id uuid
- question text not null
- status text not null default 'open'
- deliverable_url text
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
Notes:
- TODO: confirm FK for reader_id (expected app.profiles.user_id)

### app.posts
Columns:
- id uuid PK default gen_random_uuid()
- author_id uuid not null FK app.profiles(user_id) on delete cascade
- content text not null
- media_paths jsonb not null default '[]'::jsonb
- created_at timestamptz not null default now()
Indexes:
- idx_posts_author on author_id

### app.notifications
Columns:
- id uuid PK default gen_random_uuid()
- user_id uuid not null FK app.profiles(user_id) on delete cascade
- kind text not null
- payload jsonb not null default '{}'::jsonb
- is_read boolean not null default false
- created_at timestamptz not null default now()
Indexes:
- idx_notifications_user on user_id
- idx_notifications_read on (user_id, is_read)

### app.follows
Columns:
- follower_id uuid not null FK app.profiles(user_id) on delete cascade
- followee_id uuid not null FK app.profiles(user_id) on delete cascade
- created_at timestamptz not null default now()
Constraints:
- primary key (follower_id, followee_id)

### app.messages
Columns:
- id uuid PK default gen_random_uuid()
- channel text
- sender_id uuid FK app.profiles(user_id) on delete set null
- recipient_id uuid FK app.profiles(user_id) on delete set null
- content text
- created_at timestamptz not null default now()
Indexes:
- idx_messages_recipient on recipient_id
- idx_messages_channel on channel

## Views (app)
- app.activities_feed (selects activity stream from app.activities)
- app.service_orders (orders joined to services and profiles)
- app.service_reviews (reviews filtered to service_id is not null)

## Functions (app)
- set_updated_at() -> trigger
- touch_course_display_priorities() -> trigger
- touch_teacher_profile_media() -> trigger
- touch_course_entitlements() -> trigger
- touch_livekit_webhook_jobs() -> trigger
- is_admin(p_user uuid) -> boolean
- is_seminar_host(p_seminar_id uuid, p_user_id uuid) -> boolean
- is_seminar_host(p_seminar_id uuid) -> boolean
- is_seminar_attendee(p_seminar_id uuid, p_user_id uuid) -> boolean
- is_seminar_attendee(p_seminar_id uuid) -> boolean
- can_access_seminar(p_seminar_id uuid, p_user_id uuid) -> boolean
- can_access_seminar(p_seminar_id uuid) -> boolean
- grade_quiz_and_issue_certificate(p_quiz_id uuid, p_answers jsonb) -> table(passed boolean, score integer)

## Triggers (app)
- app.set_updated_at on: courses, modules, lessons, services, orders, payments, sessions, session_slots,
  seminars, seminar_sessions, seminar_recordings, profiles, teacher_approvals, teacher_payout_methods,
  teachers, course_products
- app.touch_course_display_priorities on: course_display_priorities
- app.touch_teacher_profile_media on: teacher_profile_media
- app.touch_course_entitlements on: course_entitlements
- app.touch_livekit_webhook_jobs on: livekit_webhook_jobs

## RLS Policies (intent)
Global:
- service_role_full_access on all app tables (service_role can read/write everything).
- app.course_entitlements additionally uses FORCE RLS.

Table-specific intent policies:
- app.profiles: self read/write or admin
- app.courses: public read for published; owner/admin write
- app.modules: owner/admin via course
- app.lessons: owner/admin read/write; intro lessons readable for enrolled or published intro
- app.media_objects: owner/admin read/write
- app.lesson_media: owner/admin write; read for enrolled or published intro
- app.enrollments: owner/admin or course owner read; owner/admin write
- app.services: public read when active; owner/admin write
- app.orders: user/admin read; service provider read; user/admin insert
- app.payments: readable by order owner/admin/provider
- app.teacher_payout_methods: owner/admin read/write
- app.seminars: public read for scheduled/live/ended; host/admin write
- app.seminar_attendees: attendee/admin/host read/write
- app.seminar_sessions: host/admin read/write
- app.seminar_recordings: host/admin read; public when seminar live/ended
- app.activities: authenticated read
- app.posts: author/admin read/write
- app.notifications: user/admin read/write
- app.follows: follower/admin read/write
- app.messages: sender/recipient/admin read/write
- app.course_display_priorities: owner/admin read/write
- app.teacher_profile_media: teacher/admin write; public read when is_published
- app.teachers: owner/admin read/write
- app.sessions: public read when published; owner/admin write
- app.session_slots: owner/admin write via session
- app.memberships: self/admin read
- app.reviews: reviewer/admin read/write
- app.course_bundles: public read when active; owner write
- app.course_bundle_courses: owner write via bundle
- app.course_entitlements: self/admin read
- app.course_products: course owner/admin read/write
- app.entitlements: student/admin read; teacher/admin read
- app.purchases: owner read
- app.meditations, app.tarot_requests, app.certificates, app.subscriptions, app.payment_events,
  app.billing_logs, app.auth_events, app.refresh_tokens, app.stripe_customers, app.app_config:
  service_role only (no additional policies beyond service_role_full_access)

## Storage Buckets and Policies
Buckets:
- public-media (public)
- course-media (private)
- lesson-media (private)
Policies on storage.objects:
- storage_service_role_full_access: service_role can read/write all objects
- storage_public_read: public read for bucket_id = 'public-media'

## Excluded Objects
- public.subscription_plans, public.coupons, public.subscriptions, public.user_certifications
  (referenced by backend; no repo migrations define them; schema and types are TODO outside this contract)
- Remote-only drift objects not captured in repo snapshots
