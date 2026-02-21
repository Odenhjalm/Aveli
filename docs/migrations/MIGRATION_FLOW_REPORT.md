# Migration Flow Report

## Scope and Ordering
- Source: supabase/migrations (includes _pending_local for analysis).
- Execution order: lexicographic by filename (Supabase behavior).
- Note: Supabase CLI ignores subdirectories; _pending_local is included for audit completeness.

## Execution Order (Lexical)
1. 001_app_schema.sql
2. 002_teacher_catalog.sql
3. 003_sessions_and_orders.sql
4. 004_memberships_billing.sql
5. 005_course_entitlements.sql
6. 006_course_pricing.sql
7. 007_rls_policies.sql
8. 008_rls_app_policies.sql
9. 010_fix_livekit_job_id.sql
10. 011_seminar_host_helper.sql
11. 012_seminar_access_wrapper.sql
12. 013_seminar_attendee_wrapper.sql
13. 014_seminar_host_guard.sql
14. 015_profile_stripe_customer.sql
15. 016_course_bundles.sql
16. 017_order_type_bundle.sql
17. 018_storage_buckets.sql
18. 202511180129_sync_livekit_webhook_jobs.sql
19. 20251215090000_livekit_webhook_jobs.sql
20. 20251215090100_seminar_sessions.sql
21. 20251215090200_add_next_run_at_to_livekit_webhook_jobs.sql
22. 20260102113500_live_events_rls.sql
23. 20260102113600_storage_public_media.sql
24. 20260102113700_sync_live_db_drift.sql
25. 20260110_001_course_entitlements_rls.sql
26. _pending_local/20260110_90000_rls_baseline_late_tables.sql (not applied by Supabase CLI)
27. 20260114191000_backfill_purchases_entitlements.sql
28. 20260114191010_backfill_purchases_entitlements_rls.sql

## Per-Migration Detail

### 001_app_schema.sql
Creates:
- Extensions: pgcrypto, uuid-ossp.
- Schemas: auth, app.
- Types: app.profile_role, app.user_role, app.order_status, app.payment_status, app.enrollment_source, app.service_status, app.seminar_status, app.activity_kind, app.review_visibility.
- Functions: app.set_updated_at(); app.is_seminar_host(uuid, uuid); app.is_seminar_attendee(uuid, uuid); app.can_access_seminar(uuid, uuid).
- Tables:
  - app.profiles: user_id uuid, email text, display_name text, role app.profile_role, role_v2 app.user_role, bio text, photo_url text, is_admin boolean, created_at timestamptz, updated_at timestamptz.
  - app.courses: id uuid, slug text, title text, description text, cover_url text, video_url text, branch text, is_free_intro boolean, price_cents integer, currency text, is_published boolean, created_by uuid, created_at timestamptz, updated_at timestamptz.
  - app.modules: id uuid, course_id uuid, title text, summary text, position integer, created_at timestamptz, updated_at timestamptz.
  - app.lessons: id uuid, module_id uuid, title text, content_markdown text, video_url text, duration_seconds integer, is_intro boolean, position integer, created_at timestamptz, updated_at timestamptz.
  - app.media_objects: id uuid, owner_id uuid, storage_path text, storage_bucket text, content_type text, byte_size bigint, checksum text, original_name text, created_at timestamptz, updated_at timestamptz.
  - app.lesson_media: id uuid, lesson_id uuid, kind text, media_id uuid, storage_path text, storage_bucket text, duration_seconds integer, position integer, created_at timestamptz.
  - app.enrollments: id uuid, user_id uuid, course_id uuid, status text, source app.enrollment_source, created_at timestamptz.
  - app.services: id uuid, provider_id uuid, title text, description text, status app.service_status, price_cents integer, currency text, duration_min integer, requires_certification boolean, certified_area text, thumbnail_url text, active boolean, created_at timestamptz, updated_at timestamptz.
  - app.orders: id uuid, user_id uuid, course_id uuid, service_id uuid, amount_cents integer, currency text, status app.order_status, stripe_checkout_id text, stripe_payment_intent text, metadata jsonb, created_at timestamptz, updated_at timestamptz.
  - app.payments: id uuid, order_id uuid, provider text, provider_reference text, status app.payment_status, amount_cents integer, currency text, metadata jsonb, raw_payload jsonb, created_at timestamptz, updated_at timestamptz.
  - app.teacher_payout_methods: id uuid, teacher_id uuid, provider text, reference text, details jsonb, is_default boolean, created_at timestamptz, updated_at timestamptz.
  - app.seminars: id uuid, host_id uuid, title text, description text, status app.seminar_status, scheduled_at timestamptz, duration_minutes integer, livekit_room text, livekit_metadata jsonb, recording_url text, created_at timestamptz, updated_at timestamptz.
  - app.seminar_attendees: seminar_id uuid, user_id uuid, role text, joined_at timestamptz, created_at timestamptz.
  - app.activities: id uuid, activity_type app.activity_kind, actor_id uuid, subject_table text, subject_id uuid, summary text, metadata jsonb, occurred_at timestamptz, created_at timestamptz.
  - app.refresh_tokens: id uuid, user_id uuid, jti uuid, token_hash text, issued_at timestamptz, expires_at timestamptz, rotated_at timestamptz, revoked_at timestamptz, last_used_at timestamptz.
  - app.auth_events: id uuid, user_id uuid, email text, event text, ip_address inet, user_agent text, metadata jsonb, created_at timestamptz.
  - app.posts: id uuid, author_id uuid, content text, media_paths jsonb, created_at timestamptz.
  - app.notifications: id uuid, user_id uuid, payload jsonb, read_at timestamptz, created_at timestamptz.
  - app.follows: follower_id uuid, followee_id uuid, created_at timestamptz.
  - app.app_config: id integer, free_course_limit integer, platform_fee_pct numeric.
  - app.messages: id uuid, channel text, sender_id uuid, recipient_id uuid, content text, created_at timestamptz.
  - app.stripe_customers: user_id uuid, customer_id text, created_at timestamptz, updated_at timestamptz.
  - app.teacher_permissions: profile_id uuid, can_edit_courses boolean, can_publish boolean, granted_by uuid, granted_at timestamptz.
  - app.teacher_directory: user_id uuid, headline text, specialties text[], rating numeric(3,2), created_at timestamptz.
  - app.teacher_approvals: id uuid, user_id uuid, reviewer_id uuid, status text, notes text, approved_by uuid, approved_at timestamptz, created_at timestamptz, updated_at timestamptz.
  - app.certificates: id uuid, user_id uuid, course_id uuid, title text, status text, notes text, evidence_url text, issued_at timestamptz, metadata jsonb, created_at timestamptz, updated_at timestamptz.
  - app.course_quizzes: id uuid, course_id uuid, title text, pass_score integer, created_by uuid, created_at timestamptz.
  - app.quiz_questions: id uuid, course_id uuid, quiz_id uuid, position integer, kind text, prompt text, options jsonb, correct text, created_at timestamptz, updated_at timestamptz.
  - app.meditations: id uuid, title text, description text, teacher_id uuid, media_id uuid, audio_path text, duration_seconds integer, is_public boolean, created_by uuid, created_at timestamptz.
  - app.tarot_requests: id uuid, requester_id uuid, question text, status text, created_at timestamptz.
  - app.reviews: id uuid, course_id uuid, service_id uuid, order_id uuid, reviewer_id uuid, rating integer, comment text, visibility app.review_visibility, created_at timestamptz.
- Views: app.service_orders, app.activities_feed, app.service_reviews.
- Triggers: trg_courses_touch, trg_modules_touch, trg_lessons_touch, trg_services_touch, trg_orders_touch, trg_payments_touch, trg_seminars_touch, trg_profiles_touch, trg_teacher_approvals_touch, trg_teacher_payout_methods_touch.
Alters:
- app.profiles add avatar_media_id uuid.
Policies: none.
Dependencies:
- auth.users (FK targets), auth schema, pgcrypto (gen_random_uuid), uuid-ossp (extension install).
Replay hazards: none.

### 002_teacher_catalog.sql
Creates:
- Tables:
  - app.course_display_priorities: teacher_id uuid, priority integer, notes text, updated_by uuid, created_at timestamptz, updated_at timestamptz.
  - app.teacher_profile_media: id uuid, teacher_id uuid, media_kind text, media_id uuid, external_url text, title text, description text, cover_media_id uuid, cover_image_url text, position integer, is_published boolean, metadata jsonb, created_at timestamptz, updated_at timestamptz.
- Functions: app.touch_course_display_priorities(); app.touch_teacher_profile_media().
- Triggers: trg_course_display_priorities_touch, trg_teacher_profile_media_touch.
Policies: none.
Dependencies:
- app.profiles, app.lesson_media, app.media_objects.
Replay hazards: none.

### 003_sessions_and_orders.sql
Creates:
- Types: app.session_visibility, app.order_type.
- Tables:
  - app.teachers: id uuid, profile_id uuid, stripe_connect_account_id text, payout_split_pct integer, onboarded_at timestamptz, charges_enabled boolean, payouts_enabled boolean, requirements_due jsonb, status text, created_at timestamptz, updated_at timestamptz.
  - app.sessions: id uuid, teacher_id uuid, title text, description text, start_at timestamptz, end_at timestamptz, capacity integer, price_cents integer, currency text, visibility app.session_visibility, recording_url text, stripe_price_id text, created_at timestamptz, updated_at timestamptz.
  - app.session_slots: id uuid, session_id uuid, start_at timestamptz, end_at timestamptz, seats_total integer, seats_taken integer, created_at timestamptz, updated_at timestamptz.
- Triggers: trg_teachers_touch, trg_sessions_touch, trg_session_slots_touch.
Alters:
- app.orders add order_type app.order_type, session_id uuid, session_slot_id uuid, stripe_subscription_id text, connected_account_id text, stripe_customer_id text.
Policies: none.
Dependencies:
- app.profiles, app.orders, app.set_updated_at().
Replay hazards: none.

### 004_memberships_billing.sql
Creates:
- Tables:
  - app.memberships: membership_id uuid, user_id uuid, plan_interval text, price_id text, stripe_customer_id text, stripe_subscription_id text, start_date timestamptz, end_date timestamptz, status text, created_at timestamptz, updated_at timestamptz.
  - app.payment_events: id uuid, event_id text, payload jsonb, processed_at timestamptz.
  - app.billing_logs: id uuid, user_id uuid, step text, info jsonb, created_at timestamptz.
Policies: none.
Dependencies:
- auth.users (FK target).
Replay hazards: none.

### 005_course_entitlements.sql
Creates:
- Table app.course_entitlements: id uuid, user_id uuid, course_slug text, stripe_customer_id text, stripe_payment_intent_id text, created_at timestamptz, updated_at timestamptz.
- Function: app.touch_course_entitlements().
- Trigger: trg_course_entitlements_touch.
Policies: none.
Dependencies:
- auth.users (FK target).
Replay hazards: none.

### 006_course_pricing.sql
Alters:
- app.courses add stripe_product_id text, stripe_price_id text, price_amount_cents integer, currency text.
- Data update: app.courses.price_amount_cents = app.courses.price_cents.
Policies: none.
Dependencies:
- app.courses.
Replay hazards: none.

### 007_rls_policies.sql
Creates:
- RLS enablement + service_role_full_access policy for: profiles, courses, modules, lessons, media_objects, lesson_media, enrollments, services, orders, payments, teacher_payout_methods, seminars, seminar_attendees, seminar_sessions, seminar_recordings, activities, refresh_tokens, auth_events, posts, notifications, follows, app_config, messages, stripe_customers, teacher_permissions, teacher_directory, teacher_approvals, certificates, course_quizzes, quiz_questions, meditations, tarot_requests, reviews, course_display_priorities, teacher_profile_media, teachers, sessions, session_slots, memberships, payment_events, billing_logs, livekit_webhook_jobs.
Dependencies:
- auth.role(), to_regclass, all tables listed above (guarded if missing).
Replay hazards:
- H3/H4 (RLS applied before late tables exist; guarded and therefore skipped).

### 008_rls_app_policies.sql
Creates:
- Function: app.is_admin(uuid).
- RLS enablement on tables: profiles, courses, modules, lessons, media_objects, lesson_media, enrollments, services, orders, payments, teacher_payout_methods, seminars, seminar_attendees, activities, refresh_tokens, auth_events, posts, notifications, follows, messages, stripe_customers, teacher_permissions, teacher_directory, teacher_approvals, certificates, course_quizzes, quiz_questions, meditations, tarot_requests, reviews, course_display_priorities, teacher_profile_media, teachers, sessions, session_slots, memberships, payment_events, billing_logs; plus guarded enablement for seminar_sessions, seminar_recordings, livekit_webhook_jobs.
- Policies (by table):
  - app.profiles: service_role_full_access, profiles_self_read, profiles_self_write.
  - app.courses: courses_service_role, courses_public_read, courses_owner_write.
  - app.modules: modules_service_role, modules_course_owner.
  - app.lessons: lessons_service_role, lessons_select, lessons_write.
  - app.media_objects: media_service_role, media_owner_rw.
  - app.lesson_media: lesson_media_service, lesson_media_select, lesson_media_write.
  - app.enrollments: enrollments_service, enrollments_user.
  - app.services: services_service, services_public_read, services_owner_rw.
  - app.orders: orders_service, orders_user_read, orders_user_write.
  - app.payments: payments_service, payments_read.
  - app.teacher_payout_methods: payout_service, payout_teacher.
  - app.seminars: seminars_service, seminars_public_read, seminars_host_rw.
  - app.seminar_attendees: attendees_service, attendees_read, attendees_write.
  - app.seminar_sessions (guarded): seminar_sessions_service, seminar_sessions_host.
  - app.seminar_recordings (guarded): seminar_recordings_service, seminar_recordings_read.
  - app.activities: activities_service, activities_read.
  - app.refresh_tokens: refresh_tokens_service.
  - app.auth_events: auth_events_service.
  - app.posts: posts_service, posts_author.
  - app.notifications: notifications_user.
  - app.follows: follows_user.
  - app.messages: messages_user.
  - app.stripe_customers: stripe_customers_service.
  - app.teacher_permissions: teacher_meta_service.
  - app.teacher_directory: teacher_directory_service.
  - app.teacher_approvals: teacher_approvals_service.
  - app.certificates: certificates_service.
  - app.course_quizzes: quizzes_service.
  - app.quiz_questions: quiz_questions_service.
  - app.meditations: meditations_service.
  - app.tarot_requests: tarot_service.
  - app.reviews: reviews_service, reviews_user.
  - app.course_display_priorities: course_display_service, course_display_owner.
  - app.teacher_profile_media: tpm_teacher, tpm_public_read.
  - app.teachers: teachers_service, teachers_owner.
  - app.sessions: sessions_service, sessions_public_read, sessions_owner.
  - app.session_slots: session_slots_service, session_slots_owner.
  - app.memberships: memberships_service, memberships_self.
  - app.payment_events: payment_events_service.
  - app.billing_logs: billing_logs_service.
  - app.livekit_webhook_jobs (guarded): livekit_jobs_service.
Dependencies:
- app.is_admin(), auth.uid(), auth.role(), all referenced tables.
Replay hazards:
- H3/H4 (guarded RLS for late tables).

### 010_fix_livekit_job_id.sql
Creates/Alters:
- app.livekit_webhook_jobs: rename job_id -> id, attempts -> attempt; add next_run_at; create function app.touch_livekit_webhook_jobs(); recreate trigger trg_livekit_webhook_jobs_touch.
Policies: none.
Dependencies:
- app.livekit_webhook_jobs.
Replay hazards:
- H2 (guarded skip because table is created later in the order).

### 011_seminar_host_helper.sql
Creates:
- Function: app.is_seminar_host(uuid).
Policies: none.
Dependencies:
- app.is_seminar_host(uuid, uuid), auth.uid().
Replay hazards: none.

### 012_seminar_access_wrapper.sql
Creates:
- Function: app.can_access_seminar(uuid).
Policies: none.
Dependencies:
- app.can_access_seminar(uuid, uuid), auth.uid().
Replay hazards: none.

### 013_seminar_attendee_wrapper.sql
Creates:
- Function: app.is_seminar_attendee(uuid).
Policies: none.
Dependencies:
- app.is_seminar_attendee(uuid, uuid), auth.uid().
Replay hazards: none.

### 014_seminar_host_guard.sql
Creates/Alters:
- Function: app.is_seminar_host(uuid, uuid) redefined with auth.role/auth.uid guard.
- Function: app.is_seminar_host(uuid) redefined wrapper.
Policies: none.
Dependencies:
- app.seminars, auth.role(), auth.uid().
Replay hazards: none.

### 015_profile_stripe_customer.sql
Alters:
- app.profiles add stripe_customer_id text.
- Index on lower(stripe_customer_id).
Policies: none.
Dependencies:
- app.profiles.
Replay hazards: none.

### 016_course_bundles.sql
Creates:
- Tables:
  - app.course_bundles: id uuid, teacher_id uuid, title text, description text, stripe_product_id text, stripe_price_id text, price_amount_cents integer, currency text, is_active boolean, created_at timestamptz, updated_at timestamptz.
  - app.course_bundle_courses: bundle_id uuid, course_id uuid, position integer.
- RLS enablement for app.course_bundles, app.course_bundle_courses.
- Policies: course_bundles_public_read, course_bundles_owner_write, course_bundle_courses_owner.
Dependencies:
- app.profiles, app.courses, auth.uid().
Replay hazards: none.

### 017_order_type_bundle.sql
Alters:
- app.order_type add enum value 'bundle'.
Dependencies:
- app.order_type.
Replay hazards:
- H8 (transaction safety depends on migration runner).

### 018_storage_buckets.sql
Creates:
- Storage buckets: public-media (public), course-media (private), lesson-media (private).
Dependencies:
- storage.buckets (Supabase storage schema).
Replay hazards:
- H5 (fails if storage schema is missing).

### 202511180129_sync_livekit_webhook_jobs.sql
Creates/Alters:
- app.livekit_webhook_jobs: rename job_id -> id, attempts -> attempt, error -> last_error, last_attempted_at -> last_attempt_at; add next_run_at; set attempt default/not null.
Dependencies:
- app.livekit_webhook_jobs (guarded).
Replay hazards:
- H2 (guarded skip before table creation).

### 20251215090000_livekit_webhook_jobs.sql
Creates:
- Table app.livekit_webhook_jobs: job_id uuid, event text, payload jsonb, status text, attempts integer, error text, scheduled_at timestamptz, locked_at timestamptz, last_attempted_at timestamptz, created_at timestamptz, updated_at timestamptz.
- Trigger: trg_livekit_webhook_jobs_touch (uses app.set_updated_at).
Dependencies:
- app.set_updated_at().
Replay hazards:
- H2 (schema does not match backend expectations without later fixes).

### 20251215090100_seminar_sessions.sql
Creates:
- Type: app.seminar_session_status.
- Tables:
  - app.seminar_sessions: id uuid, seminar_id uuid, status app.seminar_session_status, scheduled_at timestamptz, started_at timestamptz, ended_at timestamptz, livekit_room text, livekit_sid text, metadata jsonb, created_at timestamptz, updated_at timestamptz.
  - app.seminar_recordings: id uuid, seminar_id uuid, session_id uuid, asset_url text, status text, duration_seconds integer, byte_size bigint, published boolean, metadata jsonb, created_at timestamptz, updated_at timestamptz.
- Triggers: trg_seminar_sessions_touch, trg_seminar_recordings_touch.
Alters:
- app.seminar_attendees add invite_status text, left_at timestamptz, livekit_identity text, livekit_participant_sid text, livekit_room text.
Dependencies:
- app.seminars, app.seminar_attendees, app.set_updated_at().
Replay hazards:
- H3 (RLS/policies for these tables were skipped earlier).

### 20251215090200_add_next_run_at_to_livekit_webhook_jobs.sql
Alters:
- app.livekit_webhook_jobs add next_run_at timestamptz.
Dependencies:
- app.livekit_webhook_jobs (if exists).
Replay hazards:
- H2 (does not resolve column naming drift by itself).

### 20260102113500_live_events_rls.sql
Creates:
- RLS enablement + policies for app.live_events and app.live_event_registrations.
- Inserts migration record into supabase_migrations.schema_migrations.
Dependencies:
- app.live_events, app.live_event_registrations, app.memberships, app.enrollments, app.is_admin().
Replay hazards:
- H1 (tables are not created anywhere in migrations; migration fails on fresh DB).

### 20260102113600_storage_public_media.sql
Creates:
- Storage bucket upserts: public-media (public), course-media (private), lesson-media (private).
- Inserts migration record into supabase_migrations.schema_migrations.
Dependencies:
- storage.buckets, supabase_migrations.schema_migrations.
Replay hazards:
- H5 (storage schema dependency).

### 20260102113700_sync_live_db_drift.sql
Creates:
- No schema changes; inserts migration record into supabase_migrations.schema_migrations.
Dependencies:
- supabase_migrations.schema_migrations.
Replay hazards:
- H6 (drift marker; remote-only migrations not represented in local files).

### 20260110_001_course_entitlements_rls.sql
Creates:
- RLS enablement and policies for app.course_entitlements (service_role_full_access, course_entitlements_self_read).
Dependencies:
- app.course_entitlements, app.is_admin().
Replay hazards:
- H7 (date-only prefix + mixed numbering scheme).

### _pending_local/20260110_90000_rls_baseline_late_tables.sql
Creates:
- RLS enablement + service_role_full_access policies for seminar_sessions, seminar_recordings, livekit_webhook_jobs (guarded).
Dependencies:
- app.seminar_sessions, app.seminar_recordings, app.livekit_webhook_jobs (guarded).
Replay hazards:
- H3/H4 (file not applied by default; late tables remain without policies).

### 20260114191000_backfill_purchases_entitlements.sql
Creates:
- Tables:
  - app.purchases: id uuid, user_id uuid, order_id uuid, stripe_payment_intent text, created_at timestamptz.
  - app.course_products: id uuid, course_id uuid, stripe_product_id text, stripe_price_id text, price_amount integer, price_currency text, is_active boolean, created_at timestamptz, updated_at timestamptz.
  - app.entitlements: id uuid, user_id uuid, course_id uuid, source text, stripe_session_id text, created_at timestamptz.
  - app.guest_claim_tokens: id uuid, token text, purchase_id uuid, course_id uuid, used boolean, expires_at timestamptz, created_at timestamptz.
- Adds PK/FK/indexes inside guarded DO blocks.
- Trigger: trg_course_products_updated (uses app.set_updated_at if present).
Dependencies:
- app.profiles, app.orders, app.courses, app.set_updated_at().
Replay hazards: none.

### 20260114191010_backfill_purchases_entitlements_rls.sql
Creates:
- RLS enablement + policies for app.course_products, app.entitlements, app.guest_claim_tokens, app.purchases (guarded).
Dependencies:
- app.is_admin(), app.courses, auth.uid(), auth.role().
Replay hazards: none.

## Replay Hazards (with Remedies)

H1 (P0) Missing tables for live events
- File: supabase/migrations/20260102113500_live_events_rls.sql:6-7
- Snippet: `alter table app.live_events enable row level security;`
- Why: app.live_events and app.live_event_registrations are never created in migrations, so a fresh DB fails here.
- Remedy: add a migration that creates these tables before RLS or guard this file with to_regclass and move policies later.

H2 (P1) LiveKit job schema drift due to ordering
- Files: supabase/migrations/010_fix_livekit_job_id.sql:10-29; supabase/migrations/202511180129_sync_livekit_webhook_jobs.sql:10-23; supabase/migrations/20251215090000_livekit_webhook_jobs.sql:6-17
- Snippet: `create table if not exists app.livekit_webhook_jobs (job_id uuid ... attempts integer ... error text ... last_attempted_at timestamptz ...)`
- Why: the normalization migrations run before the table exists and are skipped; fresh replay leaves old columns while backend expects id/attempt/last_error/last_attempt_at/next_run_at.
- Remedy: move normalization into a post-create migration or rebuild so the table is created with correct column names.

H3 (P1) RLS for seminar_sessions and seminar_recordings runs before table exists
- Files: supabase/migrations/007_rls_policies.sql:8-33; supabase/migrations/008_rls_app_policies.sql:353-410
- Snippet: `if to_regclass('app.seminar_sessions') is null then raise notice ... else execute $sql$alter table app.seminar_sessions enable row level security$sql$;`
- Why: tables are created later in 20251215090100; guarded blocks skip, leaving no RLS/policies unless _pending_local is applied.
- Remedy: add a new migration after 20251215090100 to enable RLS + policies.

H4 (P1) RLS for livekit_webhook_jobs runs before table exists
- Files: supabase/migrations/007_rls_policies.sql:8-33; supabase/migrations/008_rls_app_policies.sql:631-644
- Snippet: `if to_regclass('app.livekit_webhook_jobs') is null then raise notice ...`
- Why: table is created later; guarded blocks skip, leaving no RLS/policies unless _pending_local is applied.
- Remedy: add a post-create migration to enable RLS + policies.

H5 (P1) storage.buckets dependency
- Files: supabase/migrations/018_storage_buckets.sql:4-13; supabase/migrations/20260102113600_storage_public_media.sql:6-16
- Snippet: `insert into storage.buckets (id, name, public) values ('public-media', 'public-media', true)`
- Why: fails on a fresh DB if storage schema is not installed.
- Remedy: ensure storage is installed before migrations or guard with to_regclass('storage.buckets').

H6 (P2) Drift marker migration (not source-of-truth)
- File: supabase/migrations/20260102113700_sync_live_db_drift.sql:9-14
- Snippet: `insert into supabase_migrations.schema_migrations (version, name) values ('20260102113700', 'sync_live_db_drift')`
- Why: marks migrations as applied without creating schema; listed remote-only migrations remain missing on replay.
- Remedy: convert listed remote-only changes into real migrations or a new v2 chain.

H7 (P2) Date-only prefix + mixed prefix schemes
- Files: supabase/migrations/20260110_001_course_entitlements_rls.sql:1; supabase/migrations/_pending_local/20260110_90000_rls_baseline_late_tables.sql:1; supabase/migrations/010_fix_livekit_job_id.sql:1
- Snippet: filename prefixes `20260110_...` and numeric `010_...` combined with timestamped migrations.
- Why: lexicographic ordering can misplace fixes relative to creators (e.g., livekit fixes run before the livekit table).
- Remedy: adopt full 14-digit timestamps for all new migrations and move fixes after creators.

H8 (P2) ALTER TYPE in transaction
- File: supabase/migrations/017_order_type_bundle.sql:1
- Snippet: `alter type app.order_type add value if not exists 'bundle';`
- Why: `ALTER TYPE ... ADD VALUE` fails if migrations are run inside a transaction (runner-dependent).
- Remedy: run outside a transaction or isolate in a no-transaction migration.

## Consistency Checks
- Duplicate version prefixes: none detected (no identical filename prefixes).
- Date-only prefixes: 20260110_001_course_entitlements_rls.sql and _pending_local/20260110_90000_rls_baseline_late_tables.sql use 8-digit date prefixes.
- Timestamp vs numeric ordering: numeric migrations (001-018) are ordered before timestamped migrations, which causes livekit fix migrations (010, 202511180129) to run before the livekit table is created (20251215090000).
- Drift marker migrations: 20260102113700_sync_live_db_drift.sql (and the schema_migrations inserts in 20260102113500/20260102113600) indicate remote-only changes not represented in local migrations.

## Dependency Graph (Object -> First Creator -> Modifiers)

### Tables
- app.profiles -> 001_app_schema.sql -> 001_app_schema.sql (avatar_media_id), 015_profile_stripe_customer.sql (stripe_customer_id).
- app.courses -> 001_app_schema.sql -> 006_course_pricing.sql (stripe_product_id, stripe_price_id, price_amount_cents, currency).
- app.modules -> 001_app_schema.sql -> none.
- app.lessons -> 001_app_schema.sql -> none.
- app.media_objects -> 001_app_schema.sql -> none.
- app.lesson_media -> 001_app_schema.sql -> none.
- app.enrollments -> 001_app_schema.sql -> none.
- app.services -> 001_app_schema.sql -> none.
- app.orders -> 001_app_schema.sql -> 003_sessions_and_orders.sql (order_type, session_id, session_slot_id, stripe_subscription_id, connected_account_id, stripe_customer_id).
- app.payments -> 001_app_schema.sql -> none.
- app.teacher_payout_methods -> 001_app_schema.sql -> none.
- app.seminars -> 001_app_schema.sql -> none.
- app.seminar_attendees -> 001_app_schema.sql -> 20251215090100_seminar_sessions.sql (invite_status, left_at, livekit_identity, livekit_participant_sid, livekit_room).
- app.activities -> 001_app_schema.sql -> none.
- app.refresh_tokens -> 001_app_schema.sql -> none.
- app.auth_events -> 001_app_schema.sql -> none.
- app.posts -> 001_app_schema.sql -> none.
- app.notifications -> 001_app_schema.sql -> none.
- app.follows -> 001_app_schema.sql -> none.
- app.app_config -> 001_app_schema.sql -> none.
- app.messages -> 001_app_schema.sql -> none.
- app.stripe_customers -> 001_app_schema.sql -> none.
- app.teacher_permissions -> 001_app_schema.sql -> none.
- app.teacher_directory -> 001_app_schema.sql -> none.
- app.teacher_approvals -> 001_app_schema.sql -> none.
- app.certificates -> 001_app_schema.sql -> none.
- app.course_quizzes -> 001_app_schema.sql -> none.
- app.quiz_questions -> 001_app_schema.sql -> none.
- app.meditations -> 001_app_schema.sql -> none.
- app.tarot_requests -> 001_app_schema.sql -> none.
- app.reviews -> 001_app_schema.sql -> none.
- app.course_display_priorities -> 002_teacher_catalog.sql -> none.
- app.teacher_profile_media -> 002_teacher_catalog.sql -> none.
- app.teachers -> 003_sessions_and_orders.sql -> none.
- app.sessions -> 003_sessions_and_orders.sql -> none.
- app.session_slots -> 003_sessions_and_orders.sql -> none.
- app.memberships -> 004_memberships_billing.sql -> none.
- app.payment_events -> 004_memberships_billing.sql -> none.
- app.billing_logs -> 004_memberships_billing.sql -> none.
- app.course_entitlements -> 005_course_entitlements.sql -> 20260110_001_course_entitlements_rls.sql (RLS + policies).
- app.course_bundles -> 016_course_bundles.sql -> none.
- app.course_bundle_courses -> 016_course_bundles.sql -> none.
- app.livekit_webhook_jobs -> 20251215090000_livekit_webhook_jobs.sql -> 010_fix_livekit_job_id.sql (rename/add columns, new trigger), 202511180129_sync_livekit_webhook_jobs.sql (rename/add columns), 20251215090200_add_next_run_at_to_livekit_webhook_jobs.sql (next_run_at), 007_rls_policies.sql (RLS service_role_full_access), 008_rls_app_policies.sql (livekit_jobs_service), _pending_local/20260110_90000_rls_baseline_late_tables.sql (RLS baseline).
- app.seminar_sessions -> 20251215090100_seminar_sessions.sql -> 007_rls_policies.sql (RLS service_role_full_access), 008_rls_app_policies.sql (seminar_sessions_service/seminar_sessions_host), _pending_local/20260110_90000_rls_baseline_late_tables.sql (RLS baseline).
- app.seminar_recordings -> 20251215090100_seminar_sessions.sql -> 007_rls_policies.sql (RLS service_role_full_access), 008_rls_app_policies.sql (seminar_recordings_service/seminar_recordings_read), _pending_local/20260110_90000_rls_baseline_late_tables.sql (RLS baseline).
- app.purchases -> 20260114191000_backfill_purchases_entitlements.sql -> 20260114191010_backfill_purchases_entitlements_rls.sql (RLS + policies).
- app.course_products -> 20260114191000_backfill_purchases_entitlements.sql -> 20260114191010_backfill_purchases_entitlements_rls.sql (RLS + policies).
- app.entitlements -> 20260114191000_backfill_purchases_entitlements.sql -> 20260114191010_backfill_purchases_entitlements_rls.sql (RLS + policies).
- app.guest_claim_tokens -> 20260114191000_backfill_purchases_entitlements.sql -> 20260114191010_backfill_purchases_entitlements_rls.sql (RLS + policies).

### Views
- app.service_orders -> 001_app_schema.sql -> none.
- app.activities_feed -> 001_app_schema.sql -> none.
- app.service_reviews -> 001_app_schema.sql -> none.

### Types
- app.profile_role -> 001_app_schema.sql -> none.
- app.user_role -> 001_app_schema.sql -> none.
- app.order_status -> 001_app_schema.sql -> none.
- app.payment_status -> 001_app_schema.sql -> none.
- app.enrollment_source -> 001_app_schema.sql -> none.
- app.service_status -> 001_app_schema.sql -> none.
- app.seminar_status -> 001_app_schema.sql -> none.
- app.activity_kind -> 001_app_schema.sql -> none.
- app.review_visibility -> 001_app_schema.sql -> none.
- app.session_visibility -> 003_sessions_and_orders.sql -> none.
- app.order_type -> 003_sessions_and_orders.sql -> 017_order_type_bundle.sql (add value 'bundle').
- app.seminar_session_status -> 20251215090100_seminar_sessions.sql -> none.

### Functions
- app.set_updated_at() -> 001_app_schema.sql -> none.
- app.is_seminar_host(uuid, uuid) -> 001_app_schema.sql -> 014_seminar_host_guard.sql (redefined with auth guard).
- app.is_seminar_host(uuid) -> 011_seminar_host_helper.sql -> 014_seminar_host_guard.sql (redefined).
- app.is_seminar_attendee(uuid, uuid) -> 001_app_schema.sql -> none.
- app.is_seminar_attendee(uuid) -> 013_seminar_attendee_wrapper.sql -> none.
- app.can_access_seminar(uuid, uuid) -> 001_app_schema.sql -> none.
- app.can_access_seminar(uuid) -> 012_seminar_access_wrapper.sql -> none.
- app.is_admin(uuid) -> 008_rls_app_policies.sql -> none.
- app.touch_course_display_priorities() -> 002_teacher_catalog.sql -> none.
- app.touch_teacher_profile_media() -> 002_teacher_catalog.sql -> none.
- app.touch_course_entitlements() -> 005_course_entitlements.sql -> none.
- app.touch_livekit_webhook_jobs() -> 010_fix_livekit_job_id.sql -> none (guarded creation).

### Triggers
- trg_courses_touch on app.courses -> 001_app_schema.sql -> none.
- trg_modules_touch on app.modules -> 001_app_schema.sql -> none.
- trg_lessons_touch on app.lessons -> 001_app_schema.sql -> none.
- trg_services_touch on app.services -> 001_app_schema.sql -> none.
- trg_orders_touch on app.orders -> 001_app_schema.sql -> none.
- trg_payments_touch on app.payments -> 001_app_schema.sql -> none.
- trg_seminars_touch on app.seminars -> 001_app_schema.sql -> none.
- trg_profiles_touch on app.profiles -> 001_app_schema.sql -> none.
- trg_teacher_approvals_touch on app.teacher_approvals -> 001_app_schema.sql -> none.
- trg_teacher_payout_methods_touch on app.teacher_payout_methods -> 001_app_schema.sql -> none.
- trg_course_display_priorities_touch on app.course_display_priorities -> 002_teacher_catalog.sql -> none.
- trg_teacher_profile_media_touch on app.teacher_profile_media -> 002_teacher_catalog.sql -> none.
- trg_teachers_touch on app.teachers -> 003_sessions_and_orders.sql -> none.
- trg_sessions_touch on app.sessions -> 003_sessions_and_orders.sql -> none.
- trg_session_slots_touch on app.session_slots -> 003_sessions_and_orders.sql -> none.
- trg_course_entitlements_touch on app.course_entitlements -> 005_course_entitlements.sql -> none.
- trg_livekit_webhook_jobs_touch on app.livekit_webhook_jobs -> 20251215090000_livekit_webhook_jobs.sql -> 010_fix_livekit_job_id.sql (recreate with app.touch_livekit_webhook_jobs).
- trg_seminar_sessions_touch on app.seminar_sessions -> 20251215090100_seminar_sessions.sql -> none.
- trg_seminar_recordings_touch on app.seminar_recordings -> 20251215090100_seminar_sessions.sql -> none.
- trg_course_products_updated on app.course_products -> 20260114191000_backfill_purchases_entitlements.sql -> none.

### Policies
- 007_rls_policies.sql: service_role_full_access on listed tables (see Per-Migration Detail).
- 008_rls_app_policies.sql: policies listed in Per-Migration Detail.
- 016_course_bundles.sql: course_bundles_public_read, course_bundles_owner_write, course_bundle_courses_owner.
- 20260110_001_course_entitlements_rls.sql: service_role_full_access, course_entitlements_self_read (app.course_entitlements).
- 20260102113500_live_events_rls.sql: live_events_service, live_events_access, live_events_host_rw, live_event_registrations_service, live_event_registrations_read, live_event_registrations_write.
- 20260114191010_backfill_purchases_entitlements_rls.sql: course_products_service_role, course_products_owner, entitlements_service_role, entitlements_student, entitlements_teacher, guest_claim_tokens_service_role, purchases_service_role, purchases_owner_read.
