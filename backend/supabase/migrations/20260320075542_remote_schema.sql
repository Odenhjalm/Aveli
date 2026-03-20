supabase migration repair --status reverted 20260320075057
supabase migration repair --status reverted 20260320075542drop extension if exists "pg_net";

create schema if not exists "app";

create type "app"."activity_kind" as enum ('profile_updated', 'course_published', 'lesson_published', 'service_created', 'order_paid', 'seminar_scheduled', 'room_created', 'participant_joined', 'participant_left');

create type "app"."enrollment_source" as enum ('free_intro', 'purchase', 'membership', 'grant');

create type "app"."event_participant_role" as enum ('host', 'participant');

create type "app"."event_participant_status" as enum ('registered', 'cancelled', 'attended', 'no_show');

create type "app"."event_status" as enum ('draft', 'scheduled', 'live', 'completed', 'cancelled');

create type "app"."event_type" as enum ('ceremony', 'live_class', 'course');

create type "app"."event_visibility" as enum ('public', 'members', 'invited');

create type "app"."notification_audience_type" as enum ('all_members', 'event_participants', 'course_participants', 'course_members');

create type "app"."notification_channel" as enum ('in_app', 'email');

create type "app"."notification_delivery_status" as enum ('pending', 'sent', 'failed');

create type "app"."notification_status" as enum ('pending', 'sent', 'failed');

create type "app"."notification_type" as enum ('manual', 'scheduled', 'system');

create type "app"."order_status" as enum ('pending', 'requires_action', 'processing', 'paid', 'canceled', 'failed', 'refunded');

create type "app"."order_type" as enum ('one_off', 'subscription', 'bundle');

create type "app"."payment_status" as enum ('pending', 'processing', 'paid', 'failed', 'refunded');

create type "app"."profile_role" as enum ('student', 'teacher', 'admin');

create type "app"."review_visibility" as enum ('public', 'private');

create type "app"."seminar_session_status" as enum ('scheduled', 'live', 'ended', 'failed');

create type "app"."seminar_status" as enum ('draft', 'scheduled', 'live', 'ended', 'canceled');

create type "app"."service_status" as enum ('draft', 'active', 'paused', 'archived');

create type "app"."session_visibility" as enum ('draft', 'published');

create type "app"."user_role" as enum ('user', 'professional', 'teacher');


  create table "app"."activities" (
    "id" uuid not null default gen_random_uuid(),
    "activity_type" app.activity_kind not null,
    "actor_id" uuid,
    "subject_table" text not null,
    "subject_id" uuid,
    "summary" text,
    "metadata" jsonb not null default '{}'::jsonb,
    "occurred_at" timestamp with time zone not null default now(),
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."activities" enable row level security;


  create table "app"."app_config" (
    "id" integer not null default 1,
    "free_course_limit" integer not null default 5,
    "platform_fee_pct" numeric not null default 10
      );


alter table "app"."app_config" enable row level security;


  create table "app"."auth_events" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid,
    "email" text,
    "event" text not null,
    "ip_address" inet,
    "user_agent" text,
    "metadata" jsonb,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."auth_events" enable row level security;


  create table "app"."billing_logs" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid,
    "step" text,
    "info" jsonb,
    "created_at" timestamp with time zone default now()
      );


alter table "app"."billing_logs" enable row level security;


  create table "app"."certificates" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "course_id" uuid,
    "title" text,
    "status" text not null default 'pending'::text,
    "notes" text,
    "evidence_url" text,
    "issued_at" timestamp with time zone,
    "metadata" jsonb not null default '{}'::jsonb,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."certificates" enable row level security;


  create table "app"."classroom_messages" (
    "id" uuid not null default gen_random_uuid(),
    "course_id" uuid not null,
    "user_id" uuid not null,
    "message" text not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."classroom_messages" enable row level security;


  create table "app"."classroom_presence" (
    "id" uuid not null default gen_random_uuid(),
    "course_id" uuid not null,
    "user_id" uuid not null,
    "last_seen" timestamp with time zone not null default now()
      );


alter table "app"."classroom_presence" enable row level security;


  create table "app"."course_bundle_courses" (
    "bundle_id" uuid not null,
    "course_id" uuid not null,
    "position" integer not null default 0
      );


alter table "app"."course_bundle_courses" enable row level security;


  create table "app"."course_bundles" (
    "id" uuid not null default gen_random_uuid(),
    "teacher_id" uuid not null,
    "title" text not null,
    "description" text,
    "stripe_product_id" text,
    "stripe_price_id" text,
    "price_amount_cents" integer not null default 0,
    "currency" text not null default 'sek'::text,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."course_bundles" enable row level security;


  create table "app"."course_display_priorities" (
    "teacher_id" uuid not null,
    "priority" integer not null default 1000,
    "notes" text,
    "updated_by" uuid,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."course_display_priorities" enable row level security;


  create table "app"."course_entitlements" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "course_slug" text not null,
    "stripe_customer_id" text,
    "stripe_payment_intent_id" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."course_entitlements" enable row level security;


  create table "app"."course_products" (
    "id" uuid not null default gen_random_uuid(),
    "course_id" uuid not null,
    "stripe_product_id" text not null,
    "stripe_price_id" text not null,
    "price_amount" integer not null,
    "price_currency" text not null default 'sek'::text,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."course_products" enable row level security;


  create table "app"."course_quizzes" (
    "id" uuid not null default gen_random_uuid(),
    "course_id" uuid not null,
    "title" text,
    "pass_score" integer not null default 80,
    "created_by" uuid,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."course_quizzes" enable row level security;


  create table "app"."courses" (
    "id" uuid not null default gen_random_uuid(),
    "slug" text not null,
    "title" text not null,
    "description" text,
    "cover_url" text,
    "video_url" text,
    "branch" text,
    "is_free_intro" boolean not null default false,
    "price_cents" integer not null default 0,
    "currency" text not null default 'sek'::text,
    "is_published" boolean not null default false,
    "created_by" uuid,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "stripe_product_id" text,
    "stripe_price_id" text,
    "price_amount_cents" integer not null default 0,
    "cover_media_id" uuid,
    "journey_step" text default 'intro'::text
      );


alter table "app"."courses" enable row level security;


  create table "app"."enrollments" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "course_id" uuid not null,
    "status" text not null default 'active'::text,
    "source" app.enrollment_source not null default 'purchase'::app.enrollment_source,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."enrollments" enable row level security;


  create table "app"."entitlements" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "course_id" uuid not null,
    "source" text not null,
    "stripe_session_id" text,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."entitlements" enable row level security;


  create table "app"."event_participants" (
    "id" uuid not null default gen_random_uuid(),
    "event_id" uuid not null,
    "user_id" uuid not null,
    "role" app.event_participant_role not null default 'participant'::app.event_participant_role,
    "status" app.event_participant_status not null default 'registered'::app.event_participant_status,
    "registered_at" timestamp with time zone not null default now()
      );


alter table "app"."event_participants" enable row level security;


  create table "app"."events" (
    "id" uuid not null default gen_random_uuid(),
    "type" app.event_type not null,
    "title" text not null,
    "description" text,
    "image_id" uuid,
    "start_at" timestamp with time zone not null,
    "end_at" timestamp with time zone not null,
    "timezone" text not null,
    "status" app.event_status not null default 'draft'::app.event_status,
    "visibility" app.event_visibility not null default 'invited'::app.event_visibility,
    "created_by" uuid not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."events" enable row level security;


  create table "app"."follows" (
    "follower_id" uuid not null,
    "followee_id" uuid not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."follows" enable row level security;


  create table "app"."guest_claim_tokens" (
    "id" uuid not null default gen_random_uuid(),
    "token" text not null,
    "purchase_id" uuid,
    "course_id" uuid,
    "used" boolean not null default false,
    "expires_at" timestamp with time zone not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."guest_claim_tokens" enable row level security;


  create table "app"."home_player_course_links" (
    "id" uuid not null default gen_random_uuid(),
    "teacher_id" uuid not null,
    "lesson_media_id" uuid,
    "title" text not null,
    "course_title_snapshot" text not null default ''::text,
    "enabled" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."home_player_course_links" enable row level security;


  create table "app"."home_player_uploads" (
    "id" uuid not null default gen_random_uuid(),
    "teacher_id" uuid not null,
    "media_id" uuid,
    "title" text not null,
    "kind" text not null,
    "active" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "media_asset_id" uuid
      );


alter table "app"."home_player_uploads" enable row level security;


  create table "app"."intro_usage" (
    "user_id" uuid not null,
    "year" integer not null,
    "month" integer not null,
    "count" integer not null default 0,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );



  create table "app"."lesson_media" (
    "id" uuid not null default gen_random_uuid(),
    "lesson_id" uuid not null,
    "kind" text not null,
    "media_id" uuid,
    "storage_path" text,
    "storage_bucket" text not null default 'lesson-media'::text,
    "duration_seconds" integer,
    "position" integer not null default 0,
    "created_at" timestamp with time zone not null default now(),
    "media_asset_id" uuid
      );


alter table "app"."lesson_media" enable row level security;


  create table "app"."lesson_media_issues" (
    "lesson_media_id" uuid not null,
    "issue" text not null,
    "details" jsonb not null default '{}'::jsonb,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );



  create table "app"."lesson_packages" (
    "id" uuid not null default gen_random_uuid(),
    "lesson_id" uuid not null,
    "stripe_product_id" text not null,
    "stripe_price_id" text not null,
    "price_amount" integer not null,
    "price_currency" text not null default 'sek'::text,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."lesson_packages" enable row level security;


  create table "app"."lessons" (
    "id" uuid not null default gen_random_uuid(),
    "title" text not null,
    "content_markdown" text,
    "video_url" text,
    "duration_seconds" integer,
    "is_intro" boolean not null default false,
    "position" integer not null default 0,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "price_amount_cents" integer not null default 0,
    "price_currency" text not null default 'sek'::text,
    "course_id" uuid not null
      );


alter table "app"."lessons" enable row level security;


  create table "app"."live_event_registrations" (
    "id" uuid not null default gen_random_uuid(),
    "event_id" uuid not null,
    "user_id" uuid not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."live_event_registrations" enable row level security;


  create table "app"."live_events" (
    "id" uuid not null default gen_random_uuid(),
    "teacher_id" uuid not null,
    "title" text not null,
    "description" text,
    "scheduled_at" timestamp with time zone not null,
    "room_name" text not null,
    "access_type" text not null,
    "course_id" uuid,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "starts_at" timestamp with time zone,
    "ends_at" timestamp with time zone,
    "is_published" boolean not null default false
      );


alter table "app"."live_events" enable row level security;


  create table "app"."livekit_webhook_jobs" (
    "id" uuid not null default gen_random_uuid(),
    "event" text not null,
    "payload" jsonb not null,
    "status" text not null default 'pending'::text,
    "attempt" integer not null default 0,
    "last_error" text,
    "scheduled_at" timestamp with time zone not null default now(),
    "locked_at" timestamp with time zone,
    "last_attempt_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "next_run_at" timestamp with time zone not null default now()
      );


alter table "app"."livekit_webhook_jobs" enable row level security;


  create table "app"."media_assets" (
    "id" uuid not null default gen_random_uuid(),
    "owner_id" uuid,
    "course_id" uuid,
    "lesson_id" uuid,
    "media_type" text not null,
    "ingest_format" text not null,
    "original_object_path" text not null,
    "original_content_type" text,
    "original_filename" text,
    "original_size_bytes" bigint,
    "storage_bucket" text not null default 'course-media'::text,
    "streaming_object_path" text,
    "streaming_format" text,
    "duration_seconds" integer,
    "codec" text,
    "state" text not null,
    "error_message" text,
    "processing_attempts" integer not null default 0,
    "processing_locked_at" timestamp with time zone,
    "next_retry_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "purpose" text not null default 'lesson_audio'::text,
    "streaming_storage_bucket" text
      );



  create table "app"."media_objects" (
    "id" uuid not null default gen_random_uuid(),
    "owner_id" uuid,
    "storage_path" text not null,
    "storage_bucket" text not null default 'lesson-media'::text,
    "content_type" text,
    "byte_size" bigint not null default 0,
    "checksum" text,
    "original_name" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."media_objects" enable row level security;


  create table "app"."media_resolution_failures" (
    "id" bigint generated by default as identity not null,
    "created_at" timestamp with time zone not null default now(),
    "lesson_media_id" uuid,
    "mode" text not null,
    "reason" text not null,
    "details" jsonb not null default '{}'::jsonb
      );



  create table "app"."meditations" (
    "id" uuid not null default gen_random_uuid(),
    "title" text not null,
    "description" text,
    "teacher_id" uuid,
    "media_id" uuid,
    "audio_path" text,
    "duration_seconds" integer,
    "is_public" boolean not null default false,
    "created_by" uuid,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."meditations" enable row level security;


  create table "app"."memberships" (
    "membership_id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "plan_interval" text not null,
    "price_id" text not null,
    "stripe_customer_id" text,
    "stripe_subscription_id" text,
    "start_date" timestamp with time zone not null default now(),
    "end_date" timestamp with time zone,
    "status" text not null default 'active'::text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."memberships" enable row level security;


  create table "app"."messages" (
    "id" uuid not null default gen_random_uuid(),
    "channel" text,
    "sender_id" uuid,
    "recipient_id" uuid,
    "content" text,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."messages" enable row level security;


  create table "app"."music_tracks" (
    "id" uuid not null default gen_random_uuid(),
    "teacher_id" uuid not null,
    "title" text not null,
    "description" text,
    "duration_seconds" integer,
    "storage_path" text not null,
    "cover_image_path" text,
    "access_scope" text not null,
    "course_id" uuid,
    "is_published" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."music_tracks" enable row level security;


  create table "app"."notification_audiences" (
    "id" uuid not null default gen_random_uuid(),
    "notification_id" uuid not null,
    "audience_type" app.notification_audience_type not null,
    "event_id" uuid,
    "course_id" uuid
      );


alter table "app"."notification_audiences" enable row level security;


  create table "app"."notification_campaigns" (
    "id" uuid not null default gen_random_uuid(),
    "type" app.notification_type not null default 'manual'::app.notification_type,
    "channel" app.notification_channel not null default 'in_app'::app.notification_channel,
    "title" text not null,
    "body" text not null,
    "send_at" timestamp with time zone not null default now(),
    "created_by" uuid not null,
    "status" app.notification_status not null default 'pending'::app.notification_status,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."notification_campaigns" enable row level security;


  create table "app"."notification_deliveries" (
    "id" uuid not null default gen_random_uuid(),
    "notification_id" uuid not null,
    "user_id" uuid not null,
    "channel" app.notification_channel not null,
    "status" app.notification_delivery_status not null default 'pending'::app.notification_delivery_status,
    "sent_at" timestamp with time zone,
    "error_message" text,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."notification_deliveries" enable row level security;


  create table "app"."notifications" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "payload" jsonb not null default '{}'::jsonb,
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."notifications" enable row level security;


  create table "app"."orders" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "course_id" uuid,
    "service_id" uuid,
    "amount_cents" integer not null,
    "currency" text not null default 'sek'::text,
    "status" app.order_status not null default 'pending'::app.order_status,
    "stripe_checkout_id" text,
    "stripe_payment_intent" text,
    "metadata" jsonb not null default '{}'::jsonb,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "order_type" app.order_type not null default 'one_off'::app.order_type,
    "session_id" uuid,
    "session_slot_id" uuid,
    "stripe_subscription_id" text,
    "connected_account_id" text,
    "stripe_customer_id" text
      );


alter table "app"."orders" enable row level security;


  create table "app"."payment_events" (
    "id" uuid not null default gen_random_uuid(),
    "event_id" text not null,
    "payload" jsonb not null,
    "processed_at" timestamp with time zone default now()
      );


alter table "app"."payment_events" enable row level security;


  create table "app"."payments" (
    "id" uuid not null default gen_random_uuid(),
    "order_id" uuid not null,
    "provider" text not null,
    "provider_reference" text,
    "status" app.payment_status not null default 'pending'::app.payment_status,
    "amount_cents" integer not null,
    "currency" text not null default 'sek'::text,
    "metadata" jsonb not null default '{}'::jsonb,
    "raw_payload" jsonb,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."payments" enable row level security;


  create table "app"."posts" (
    "id" uuid not null default gen_random_uuid(),
    "author_id" uuid not null,
    "content" text not null,
    "media_paths" jsonb not null default '[]'::jsonb,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."posts" enable row level security;


  create table "app"."profiles" (
    "user_id" uuid not null,
    "email" text not null,
    "display_name" text,
    "role" app.profile_role not null default 'student'::app.profile_role,
    "role_v2" app.user_role not null default 'user'::app.user_role,
    "bio" text,
    "photo_url" text,
    "is_admin" boolean not null default false,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "avatar_media_id" uuid,
    "stripe_customer_id" text,
    "provider_name" text,
    "provider_user_id" text,
    "provider_email_verified" boolean,
    "provider_avatar_url" text,
    "last_login_provider" text,
    "last_login_at" timestamp with time zone
      );


alter table "app"."profiles" enable row level security;


  create table "app"."purchases" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "order_id" uuid,
    "stripe_payment_intent" text,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."purchases" enable row level security;


  create table "app"."quiz_questions" (
    "id" uuid not null default gen_random_uuid(),
    "course_id" uuid,
    "quiz_id" uuid,
    "position" integer not null default 0,
    "kind" text not null default 'single'::text,
    "prompt" text not null,
    "options" jsonb not null default '{}'::jsonb,
    "correct" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."quiz_questions" enable row level security;


  create table "app"."referral_codes" (
    "id" uuid not null default gen_random_uuid(),
    "code" text not null,
    "teacher_id" uuid not null,
    "email" text not null,
    "free_days" integer,
    "free_months" integer,
    "active" boolean default true,
    "redeemed_by_user_id" uuid,
    "redeemed_at" timestamp with time zone,
    "created_at" timestamp with time zone default now()
      );



  create table "app"."refresh_tokens" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "jti" uuid not null,
    "token_hash" text not null,
    "issued_at" timestamp with time zone not null default now(),
    "expires_at" timestamp with time zone not null,
    "rotated_at" timestamp with time zone,
    "revoked_at" timestamp with time zone,
    "last_used_at" timestamp with time zone
      );


alter table "app"."refresh_tokens" enable row level security;


  create table "app"."reviews" (
    "id" uuid not null default gen_random_uuid(),
    "course_id" uuid,
    "service_id" uuid,
    "order_id" uuid,
    "reviewer_id" uuid not null,
    "rating" integer not null,
    "comment" text,
    "visibility" app.review_visibility not null default 'public'::app.review_visibility,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."reviews" enable row level security;


  create table "app"."runtime_media" (
    "id" uuid not null default gen_random_uuid(),
    "reference_type" text not null,
    "auth_scope" text not null,
    "fallback_policy" text not null,
    "lesson_media_id" uuid,
    "home_player_upload_id" uuid,
    "teacher_id" uuid,
    "course_id" uuid,
    "lesson_id" uuid,
    "media_asset_id" uuid,
    "media_object_id" uuid,
    "legacy_storage_bucket" text,
    "legacy_storage_path" text,
    "kind" text not null,
    "active" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );



  create table "app"."seminar_attendees" (
    "seminar_id" uuid not null,
    "user_id" uuid not null,
    "role" text not null default 'participant'::text,
    "joined_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "invite_status" text not null default 'pending'::text,
    "left_at" timestamp with time zone,
    "livekit_identity" text,
    "livekit_participant_sid" text,
    "livekit_room" text
      );


alter table "app"."seminar_attendees" enable row level security;


  create table "app"."seminar_recordings" (
    "id" uuid not null default gen_random_uuid(),
    "seminar_id" uuid not null,
    "session_id" uuid,
    "asset_url" text,
    "status" text not null default 'processing'::text,
    "duration_seconds" integer,
    "byte_size" bigint,
    "published" boolean not null default false,
    "metadata" jsonb not null default '{}'::jsonb,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."seminar_recordings" enable row level security;


  create table "app"."seminar_sessions" (
    "id" uuid not null default gen_random_uuid(),
    "seminar_id" uuid not null,
    "status" app.seminar_session_status not null default 'scheduled'::app.seminar_session_status,
    "scheduled_at" timestamp with time zone,
    "started_at" timestamp with time zone,
    "ended_at" timestamp with time zone,
    "livekit_room" text,
    "livekit_sid" text,
    "metadata" jsonb not null default '{}'::jsonb,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."seminar_sessions" enable row level security;


  create table "app"."seminars" (
    "id" uuid not null default gen_random_uuid(),
    "host_id" uuid not null,
    "title" text not null,
    "description" text,
    "status" app.seminar_status not null default 'draft'::app.seminar_status,
    "scheduled_at" timestamp with time zone,
    "duration_minutes" integer,
    "livekit_room" text,
    "livekit_metadata" jsonb,
    "recording_url" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."seminars" enable row level security;


  create table "app"."services" (
    "id" uuid not null default gen_random_uuid(),
    "provider_id" uuid not null,
    "title" text not null,
    "description" text,
    "status" app.service_status not null default 'draft'::app.service_status,
    "price_cents" integer not null default 0,
    "currency" text not null default 'sek'::text,
    "duration_min" integer,
    "requires_certification" boolean not null default false,
    "certified_area" text,
    "thumbnail_url" text,
    "active" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."services" enable row level security;


  create table "app"."session_slots" (
    "id" uuid not null default gen_random_uuid(),
    "session_id" uuid not null,
    "start_at" timestamp with time zone not null,
    "end_at" timestamp with time zone not null,
    "seats_total" integer not null default 1,
    "seats_taken" integer not null default 0,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."session_slots" enable row level security;


  create table "app"."sessions" (
    "id" uuid not null default gen_random_uuid(),
    "teacher_id" uuid not null,
    "title" text not null,
    "description" text,
    "start_at" timestamp with time zone,
    "end_at" timestamp with time zone,
    "capacity" integer,
    "price_cents" integer not null default 0,
    "currency" text not null default 'sek'::text,
    "visibility" app.session_visibility not null default 'draft'::app.session_visibility,
    "recording_url" text,
    "stripe_price_id" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."sessions" enable row level security;


  create table "app"."stripe_customers" (
    "user_id" uuid not null,
    "customer_id" text not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."stripe_customers" enable row level security;


  create table "app"."subscriptions" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "subscription_id" text not null,
    "customer_id" text,
    "price_id" text,
    "status" text not null default 'active'::text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."subscriptions" enable row level security;


  create table "app"."tarot_requests" (
    "id" uuid not null default gen_random_uuid(),
    "requester_id" uuid not null,
    "question" text not null,
    "status" text not null default 'open'::text,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."tarot_requests" enable row level security;


  create table "app"."teacher_accounts" (
    "user_id" uuid not null,
    "stripe_account_id" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."teacher_accounts" enable row level security;


  create table "app"."teacher_approvals" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "reviewer_id" uuid,
    "status" text not null default 'pending'::text,
    "notes" text,
    "approved_by" uuid,
    "approved_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."teacher_approvals" enable row level security;


  create table "app"."teacher_directory" (
    "user_id" uuid not null,
    "headline" text,
    "specialties" text[],
    "rating" numeric(3,2),
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."teacher_directory" enable row level security;


  create table "app"."teacher_payout_methods" (
    "id" uuid not null default gen_random_uuid(),
    "teacher_id" uuid not null,
    "provider" text not null,
    "reference" text not null,
    "details" jsonb not null default '{}'::jsonb,
    "is_default" boolean not null default false,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."teacher_payout_methods" enable row level security;


  create table "app"."teacher_permissions" (
    "profile_id" uuid not null,
    "can_edit_courses" boolean not null default false,
    "can_publish" boolean not null default false,
    "granted_by" uuid,
    "granted_at" timestamp with time zone not null default now()
      );


alter table "app"."teacher_permissions" enable row level security;


  create table "app"."teacher_profile_media" (
    "id" uuid not null default gen_random_uuid(),
    "teacher_id" uuid not null,
    "media_kind" text not null,
    "media_id" uuid,
    "external_url" text,
    "title" text,
    "description" text,
    "cover_media_id" uuid,
    "cover_image_url" text,
    "position" integer not null default 0,
    "is_published" boolean not null default true,
    "metadata" jsonb not null default '{}'::jsonb,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "enabled_for_home_player" boolean not null default false,
    "visibility_intro_material" boolean not null default false,
    "visibility_course_member" boolean not null default false,
    "home_visibility_intro_material" boolean not null default false,
    "home_visibility_course_member" boolean not null default false
      );


alter table "app"."teacher_profile_media" enable row level security;


  create table "app"."teachers" (
    "id" uuid not null default gen_random_uuid(),
    "profile_id" uuid not null,
    "stripe_connect_account_id" text,
    "payout_split_pct" integer not null default 100,
    "onboarded_at" timestamp with time zone,
    "charges_enabled" boolean not null default false,
    "payouts_enabled" boolean not null default false,
    "requirements_due" jsonb not null default '{}'::jsonb,
    "status" text not null default 'pending'::text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."teachers" enable row level security;


  create table "app"."welcome_cards" (
    "id" uuid not null default gen_random_uuid(),
    "title" text,
    "body" text,
    "image_path" text not null,
    "day" integer,
    "month" integer,
    "is_active" boolean not null default true,
    "created_by" uuid not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."welcome_cards" enable row level security;


  create table "public"."coupons" (
    "code" text not null,
    "plan_id" uuid,
    "grants" jsonb not null default '{}'::jsonb,
    "max_redemptions" integer,
    "redeemed_count" integer not null default 0,
    "expires_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."coupons" enable row level security;


  create table "public"."subscription_plans" (
    "id" uuid not null default gen_random_uuid(),
    "name" text not null,
    "price_cents" integer not null,
    "interval" text not null,
    "is_active" boolean not null default true,
    "stripe_product_id" text,
    "stripe_price_id" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."subscription_plans" enable row level security;


  create table "public"."subscriptions" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "plan_id" uuid not null,
    "status" text not null default 'active'::text,
    "current_period_end" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."subscriptions" enable row level security;


  create table "public"."user_certifications" (
    "user_id" uuid not null,
    "area" text not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."user_certifications" enable row level security;

CREATE UNIQUE INDEX activities_pkey ON app.activities USING btree (id);

CREATE UNIQUE INDEX app_config_pkey ON app.app_config USING btree (id);

CREATE UNIQUE INDEX auth_events_pkey ON app.auth_events USING btree (id);

CREATE UNIQUE INDEX billing_logs_pkey ON app.billing_logs USING btree (id);

CREATE UNIQUE INDEX certificates_pkey ON app.certificates USING btree (id);

CREATE UNIQUE INDEX classroom_messages_pkey ON app.classroom_messages USING btree (id);

CREATE UNIQUE INDEX classroom_presence_course_id_user_id_key ON app.classroom_presence USING btree (course_id, user_id);

CREATE UNIQUE INDEX classroom_presence_pkey ON app.classroom_presence USING btree (id);

CREATE UNIQUE INDEX course_bundle_courses_pkey ON app.course_bundle_courses USING btree (bundle_id, course_id);

CREATE UNIQUE INDEX course_bundles_pkey ON app.course_bundles USING btree (id);

CREATE UNIQUE INDEX course_display_priorities_pkey ON app.course_display_priorities USING btree (teacher_id);

CREATE UNIQUE INDEX course_entitlements_pkey ON app.course_entitlements USING btree (id);

CREATE UNIQUE INDEX course_entitlements_user_course_key ON app.course_entitlements USING btree (user_id, course_slug);

CREATE UNIQUE INDEX course_products_course_id_key ON app.course_products USING btree (course_id);

CREATE UNIQUE INDEX course_products_pkey ON app.course_products USING btree (id);

CREATE UNIQUE INDEX course_quizzes_pkey ON app.course_quizzes USING btree (id);

CREATE UNIQUE INDEX courses_pkey ON app.courses USING btree (id);

CREATE INDEX courses_slug_idx ON app.courses USING btree (slug);

CREATE UNIQUE INDEX courses_slug_key ON app.courses USING btree (slug);

CREATE UNIQUE INDEX enrollments_pkey ON app.enrollments USING btree (id);

CREATE UNIQUE INDEX enrollments_user_id_course_id_key ON app.enrollments USING btree (user_id, course_id);

CREATE UNIQUE INDEX entitlements_pkey ON app.entitlements USING btree (id);

CREATE UNIQUE INDEX event_participants_event_id_user_id_key ON app.event_participants USING btree (event_id, user_id);

CREATE UNIQUE INDEX event_participants_pkey ON app.event_participants USING btree (id);

CREATE UNIQUE INDEX events_pkey ON app.events USING btree (id);

CREATE UNIQUE INDEX follows_pkey ON app.follows USING btree (follower_id, followee_id);

CREATE UNIQUE INDEX guest_claim_tokens_pkey ON app.guest_claim_tokens USING btree (id);

CREATE UNIQUE INDEX guest_claim_tokens_token_key ON app.guest_claim_tokens USING btree (token);

CREATE UNIQUE INDEX home_player_course_links_pkey ON app.home_player_course_links USING btree (id);

CREATE UNIQUE INDEX home_player_course_links_teacher_id_lesson_media_id_key ON app.home_player_course_links USING btree (teacher_id, lesson_media_id);

CREATE UNIQUE INDEX home_player_uploads_pkey ON app.home_player_uploads USING btree (id);

CREATE INDEX idx_activities_occurred ON app.activities USING btree (occurred_at DESC);

CREATE INDEX idx_activities_subject ON app.activities USING btree (subject_table, subject_id);

CREATE INDEX idx_activities_type ON app.activities USING btree (activity_type);

CREATE INDEX idx_auth_events_created_at ON app.auth_events USING btree (created_at DESC);

CREATE INDEX idx_auth_events_user ON app.auth_events USING btree (user_id);

CREATE INDEX idx_certificates_user ON app.certificates USING btree (user_id);

CREATE INDEX idx_classroom_messages_course ON app.classroom_messages USING btree (course_id);

CREATE INDEX idx_classroom_messages_created ON app.classroom_messages USING btree (created_at);

CREATE INDEX idx_classroom_presence_course ON app.classroom_presence USING btree (course_id);

CREATE INDEX idx_classroom_presence_last_seen ON app.classroom_presence USING btree (last_seen);

CREATE INDEX idx_course_bundle_courses_bundle ON app.course_bundle_courses USING btree (bundle_id);

CREATE INDEX idx_course_bundles_active ON app.course_bundles USING btree (is_active);

CREATE INDEX idx_course_bundles_teacher ON app.course_bundles USING btree (teacher_id);

CREATE INDEX idx_course_display_priorities_priority ON app.course_display_priorities USING btree (priority);

CREATE INDEX idx_course_entitlements_user_course ON app.course_entitlements USING btree (user_id, course_slug);

CREATE INDEX idx_course_products_course ON app.course_products USING btree (course_id);

CREATE INDEX idx_courses_cover_media ON app.courses USING btree (cover_media_id);

CREATE INDEX idx_courses_created_by ON app.courses USING btree (created_by);

CREATE INDEX idx_enrollments_course ON app.enrollments USING btree (course_id);

CREATE INDEX idx_enrollments_user ON app.enrollments USING btree (user_id);

CREATE INDEX idx_entitlements_course ON app.entitlements USING btree (course_id);

CREATE INDEX idx_entitlements_user ON app.entitlements USING btree (user_id);

CREATE INDEX idx_entitlements_user_course ON app.entitlements USING btree (user_id, course_id);

CREATE INDEX idx_event_participants_event ON app.event_participants USING btree (event_id);

CREATE INDEX idx_event_participants_user ON app.event_participants USING btree (user_id);

CREATE INDEX idx_events_created_by ON app.events USING btree (created_by);

CREATE INDEX idx_events_start_at ON app.events USING btree (start_at);

CREATE INDEX idx_events_status ON app.events USING btree (status);

CREATE INDEX idx_events_visibility ON app.events USING btree (visibility);

CREATE INDEX idx_guest_claim_tokens_expires ON app.guest_claim_tokens USING btree (expires_at);

CREATE INDEX idx_guest_claim_tokens_used ON app.guest_claim_tokens USING btree (used);

CREATE INDEX idx_home_player_course_links_teacher_created ON app.home_player_course_links USING btree (teacher_id, created_at DESC);

CREATE INDEX idx_home_player_uploads_media ON app.home_player_uploads USING btree (media_id);

CREATE INDEX idx_home_player_uploads_media_asset ON app.home_player_uploads USING btree (media_asset_id);

CREATE INDEX idx_home_player_uploads_teacher_created ON app.home_player_uploads USING btree (teacher_id, created_at DESC);

CREATE INDEX idx_intro_usage_user_month ON app.intro_usage USING btree (user_id, year DESC, month DESC);

CREATE INDEX idx_lesson_media_asset ON app.lesson_media USING btree (media_asset_id);

CREATE INDEX idx_lesson_media_issues_issue ON app.lesson_media_issues USING btree (issue);

CREATE INDEX idx_lesson_media_lesson ON app.lesson_media USING btree (lesson_id);

CREATE INDEX idx_lesson_media_media ON app.lesson_media USING btree (media_id);

CREATE INDEX idx_lesson_packages_lesson ON app.lesson_packages USING btree (lesson_id);

CREATE INDEX idx_lessons_course ON app.lessons USING btree (course_id);

CREATE INDEX idx_live_event_registrations_event ON app.live_event_registrations USING btree (event_id);

CREATE UNIQUE INDEX idx_live_event_registrations_unique ON app.live_event_registrations USING btree (event_id, user_id);

CREATE INDEX idx_live_event_registrations_user ON app.live_event_registrations USING btree (user_id);

CREATE INDEX idx_live_events_access_type ON app.live_events USING btree (access_type);

CREATE INDEX idx_live_events_course ON app.live_events USING btree (course_id);

CREATE INDEX idx_live_events_scheduled_at ON app.live_events USING btree (scheduled_at);

CREATE INDEX idx_live_events_starts_at ON app.live_events USING btree (starts_at);

CREATE INDEX idx_live_events_teacher ON app.live_events USING btree (teacher_id);

CREATE INDEX idx_livekit_webhook_jobs_status ON app.livekit_webhook_jobs USING btree (status, scheduled_at);

CREATE INDEX idx_media_assets_course ON app.media_assets USING btree (course_id);

CREATE INDEX idx_media_assets_course_cover ON app.media_assets USING btree (course_id) WHERE (purpose = 'course_cover'::text);

CREATE INDEX idx_media_assets_lesson ON app.media_assets USING btree (lesson_id);

CREATE INDEX idx_media_assets_next_retry ON app.media_assets USING btree (next_retry_at);

CREATE INDEX idx_media_assets_purpose ON app.media_assets USING btree (purpose);

CREATE INDEX idx_media_assets_state ON app.media_assets USING btree (state);

CREATE INDEX idx_media_owner ON app.media_objects USING btree (owner_id);

CREATE INDEX idx_media_resolution_failures_created_at ON app.media_resolution_failures USING btree (created_at DESC);

CREATE INDEX idx_media_resolution_failures_lesson_media ON app.media_resolution_failures USING btree (lesson_media_id);

CREATE INDEX idx_media_resolution_failures_reason ON app.media_resolution_failures USING btree (reason);

CREATE INDEX idx_messages_channel ON app.messages USING btree (channel);

CREATE INDEX idx_messages_recipient ON app.messages USING btree (recipient_id);

CREATE INDEX idx_music_tracks_course ON app.music_tracks USING btree (course_id);

CREATE INDEX idx_music_tracks_created ON app.music_tracks USING btree (created_at DESC);

CREATE INDEX idx_music_tracks_teacher ON app.music_tracks USING btree (teacher_id);

CREATE INDEX idx_notification_audiences_course ON app.notification_audiences USING btree (course_id);

CREATE INDEX idx_notification_audiences_event ON app.notification_audiences USING btree (event_id);

CREATE INDEX idx_notification_audiences_notification_id ON app.notification_audiences USING btree (notification_id);

CREATE INDEX idx_notification_campaigns_created_by ON app.notification_campaigns USING btree (created_by);

CREATE INDEX idx_notification_campaigns_send_at ON app.notification_campaigns USING btree (send_at);

CREATE INDEX idx_notification_campaigns_status ON app.notification_campaigns USING btree (status);

CREATE INDEX idx_notification_deliveries_notification_id ON app.notification_deliveries USING btree (notification_id);

CREATE INDEX idx_notification_deliveries_status ON app.notification_deliveries USING btree (status);

CREATE INDEX idx_notification_deliveries_user ON app.notification_deliveries USING btree (user_id);

CREATE INDEX idx_notifications_read ON app.notifications USING btree (user_id, read_at);

CREATE INDEX idx_notifications_user ON app.notifications USING btree (user_id);

CREATE INDEX idx_orders_connected_account ON app.orders USING btree (connected_account_id);

CREATE INDEX idx_orders_course ON app.orders USING btree (course_id);

CREATE INDEX idx_orders_service ON app.orders USING btree (service_id);

CREATE INDEX idx_orders_session ON app.orders USING btree (session_id);

CREATE INDEX idx_orders_session_slot ON app.orders USING btree (session_slot_id);

CREATE INDEX idx_orders_status ON app.orders USING btree (status);

CREATE INDEX idx_orders_user ON app.orders USING btree (user_id);

CREATE INDEX idx_payments_order ON app.payments USING btree (order_id);

CREATE INDEX idx_payments_status ON app.payments USING btree (status);

CREATE INDEX idx_payout_methods_teacher ON app.teacher_payout_methods USING btree (teacher_id);

CREATE INDEX idx_posts_author ON app.posts USING btree (author_id);

CREATE INDEX idx_purchases_order ON app.purchases USING btree (order_id);

CREATE INDEX idx_purchases_user ON app.purchases USING btree (user_id);

CREATE INDEX idx_quiz_questions_course ON app.quiz_questions USING btree (course_id);

CREATE INDEX idx_quiz_questions_quiz ON app.quiz_questions USING btree (quiz_id);

CREATE INDEX idx_refresh_tokens_user ON app.refresh_tokens USING btree (user_id);

CREATE INDEX idx_reviews_course ON app.reviews USING btree (course_id);

CREATE INDEX idx_reviews_order ON app.reviews USING btree (order_id);

CREATE INDEX idx_reviews_reviewer ON app.reviews USING btree (reviewer_id);

CREATE INDEX idx_reviews_service ON app.reviews USING btree (service_id);

CREATE INDEX idx_runtime_media_asset ON app.runtime_media USING btree (media_asset_id);

CREATE INDEX idx_runtime_media_course ON app.runtime_media USING btree (course_id);

CREATE INDEX idx_runtime_media_lesson ON app.runtime_media USING btree (lesson_id);

CREATE INDEX idx_runtime_media_object ON app.runtime_media USING btree (media_object_id);

CREATE INDEX idx_runtime_media_teacher_active ON app.runtime_media USING btree (teacher_id, active);

CREATE INDEX idx_seminar_recordings_seminar ON app.seminar_recordings USING btree (seminar_id);

CREATE INDEX idx_seminar_sessions_seminar ON app.seminar_sessions USING btree (seminar_id);

CREATE INDEX idx_seminars_host ON app.seminars USING btree (host_id);

CREATE INDEX idx_seminars_scheduled_at ON app.seminars USING btree (scheduled_at);

CREATE INDEX idx_seminars_status ON app.seminars USING btree (status);

CREATE INDEX idx_services_provider ON app.services USING btree (provider_id);

CREATE INDEX idx_services_status ON app.services USING btree (status);

CREATE INDEX idx_session_slots_session ON app.session_slots USING btree (session_id);

CREATE INDEX idx_session_slots_time ON app.session_slots USING btree (start_at, end_at);

CREATE INDEX idx_sessions_start_at ON app.sessions USING btree (start_at);

CREATE INDEX idx_sessions_teacher ON app.sessions USING btree (teacher_id);

CREATE INDEX idx_sessions_visibility ON app.sessions USING btree (visibility);

CREATE INDEX idx_subscriptions_user ON app.subscriptions USING btree (user_id);

CREATE INDEX idx_teacher_approvals_user ON app.teacher_approvals USING btree (user_id);

CREATE INDEX idx_teacher_profile_media_teacher ON app.teacher_profile_media USING btree (teacher_id, "position");

CREATE INDEX idx_teachers_connect_account ON app.teachers USING btree (stripe_connect_account_id);

CREATE INDEX idx_welcome_cards_active ON app.welcome_cards USING btree (is_active);

CREATE INDEX idx_welcome_cards_date ON app.welcome_cards USING btree (month, day);

CREATE UNIQUE INDEX intro_usage_pkey ON app.intro_usage USING btree (user_id, year, month);

CREATE UNIQUE INDEX lesson_media_issues_pkey ON app.lesson_media_issues USING btree (lesson_media_id);

CREATE UNIQUE INDEX lesson_media_lesson_id_position_key ON app.lesson_media USING btree (lesson_id, "position");

CREATE UNIQUE INDEX lesson_media_pkey ON app.lesson_media USING btree (id);

CREATE UNIQUE INDEX lesson_packages_lesson_id_key ON app.lesson_packages USING btree (lesson_id);

CREATE UNIQUE INDEX lesson_packages_pkey ON app.lesson_packages USING btree (id);

CREATE UNIQUE INDEX lessons_course_id_position_key ON app.lessons USING btree (course_id, "position");

CREATE UNIQUE INDEX lessons_pkey ON app.lessons USING btree (id);

CREATE UNIQUE INDEX live_event_registrations_pkey ON app.live_event_registrations USING btree (id);

CREATE UNIQUE INDEX live_events_pkey ON app.live_events USING btree (id);

CREATE UNIQUE INDEX livekit_webhook_jobs_pkey ON app.livekit_webhook_jobs USING btree (id);

CREATE UNIQUE INDEX media_assets_pkey ON app.media_assets USING btree (id);

CREATE UNIQUE INDEX media_objects_pkey ON app.media_objects USING btree (id);

CREATE UNIQUE INDEX media_objects_storage_path_storage_bucket_key ON app.media_objects USING btree (storage_path, storage_bucket);

CREATE UNIQUE INDEX media_resolution_failures_pkey ON app.media_resolution_failures USING btree (id);

CREATE UNIQUE INDEX meditations_pkey ON app.meditations USING btree (id);

CREATE UNIQUE INDEX memberships_pkey ON app.memberships USING btree (membership_id);

CREATE UNIQUE INDEX memberships_user_id_key ON app.memberships USING btree (user_id);

CREATE UNIQUE INDEX messages_pkey ON app.messages USING btree (id);

CREATE UNIQUE INDEX music_tracks_pkey ON app.music_tracks USING btree (id);

CREATE UNIQUE INDEX notification_audiences_pkey ON app.notification_audiences USING btree (id);

CREATE UNIQUE INDEX notification_campaigns_pkey ON app.notification_campaigns USING btree (id);

CREATE UNIQUE INDEX notification_deliveries_notification_id_user_id_channel_key ON app.notification_deliveries USING btree (notification_id, user_id, channel);

CREATE UNIQUE INDEX notification_deliveries_pkey ON app.notification_deliveries USING btree (id);

CREATE UNIQUE INDEX notifications_pkey ON app.notifications USING btree (id);

CREATE UNIQUE INDEX orders_pkey ON app.orders USING btree (id);

CREATE UNIQUE INDEX payment_events_event_id_key ON app.payment_events USING btree (event_id);

CREATE UNIQUE INDEX payment_events_pkey ON app.payment_events USING btree (id);

CREATE UNIQUE INDEX payments_pkey ON app.payments USING btree (id);

CREATE UNIQUE INDEX posts_pkey ON app.posts USING btree (id);

CREATE UNIQUE INDEX profiles_email_key ON app.profiles USING btree (email);

CREATE UNIQUE INDEX profiles_pkey ON app.profiles USING btree (user_id);

CREATE INDEX profiles_stripe_customer_idx ON app.profiles USING btree (lower(stripe_customer_id));

CREATE UNIQUE INDEX purchases_pkey ON app.purchases USING btree (id);

CREATE UNIQUE INDEX quiz_questions_pkey ON app.quiz_questions USING btree (id);

CREATE UNIQUE INDEX referral_codes_code_key ON app.referral_codes USING btree (code);

CREATE UNIQUE INDEX referral_codes_pkey ON app.referral_codes USING btree (id);

CREATE UNIQUE INDEX refresh_tokens_jti_key ON app.refresh_tokens USING btree (jti);

CREATE UNIQUE INDEX refresh_tokens_pkey ON app.refresh_tokens USING btree (id);

CREATE UNIQUE INDEX reviews_pkey ON app.reviews USING btree (id);

CREATE UNIQUE INDEX runtime_media_home_player_upload_id_key ON app.runtime_media USING btree (home_player_upload_id);

CREATE UNIQUE INDEX runtime_media_lesson_media_id_key ON app.runtime_media USING btree (lesson_media_id);

CREATE UNIQUE INDEX runtime_media_pkey ON app.runtime_media USING btree (id);

CREATE UNIQUE INDEX seminar_attendees_pkey ON app.seminar_attendees USING btree (seminar_id, user_id);

CREATE UNIQUE INDEX seminar_recordings_pkey ON app.seminar_recordings USING btree (id);

CREATE UNIQUE INDEX seminar_sessions_pkey ON app.seminar_sessions USING btree (id);

CREATE UNIQUE INDEX seminars_pkey ON app.seminars USING btree (id);

CREATE UNIQUE INDEX services_pkey ON app.services USING btree (id);

CREATE UNIQUE INDEX session_slots_pkey ON app.session_slots USING btree (id);

CREATE UNIQUE INDEX session_slots_session_id_start_at_key ON app.session_slots USING btree (session_id, start_at);

CREATE UNIQUE INDEX sessions_pkey ON app.sessions USING btree (id);

CREATE UNIQUE INDEX stripe_customers_pkey ON app.stripe_customers USING btree (user_id);

CREATE UNIQUE INDEX subscriptions_pkey ON app.subscriptions USING btree (id);

CREATE UNIQUE INDEX subscriptions_subscription_id_key ON app.subscriptions USING btree (subscription_id);

CREATE UNIQUE INDEX tarot_requests_pkey ON app.tarot_requests USING btree (id);

CREATE UNIQUE INDEX teacher_accounts_pkey ON app.teacher_accounts USING btree (user_id);

CREATE UNIQUE INDEX teacher_approvals_pkey ON app.teacher_approvals USING btree (id);

CREATE UNIQUE INDEX teacher_approvals_user_id_key ON app.teacher_approvals USING btree (user_id);

CREATE UNIQUE INDEX teacher_directory_pkey ON app.teacher_directory USING btree (user_id);

CREATE UNIQUE INDEX teacher_payout_methods_pkey ON app.teacher_payout_methods USING btree (id);

CREATE UNIQUE INDEX teacher_payout_methods_teacher_id_provider_reference_key ON app.teacher_payout_methods USING btree (teacher_id, provider, reference);

CREATE UNIQUE INDEX teacher_permissions_pkey ON app.teacher_permissions USING btree (profile_id);

CREATE UNIQUE INDEX teacher_profile_media_pkey ON app.teacher_profile_media USING btree (id);

CREATE UNIQUE INDEX teacher_profile_media_teacher_id_media_kind_media_id_key ON app.teacher_profile_media USING btree (teacher_id, media_kind, media_id);

CREATE UNIQUE INDEX teachers_pkey ON app.teachers USING btree (id);

CREATE UNIQUE INDEX teachers_profile_id_key ON app.teachers USING btree (profile_id);

CREATE UNIQUE INDEX teachers_stripe_connect_account_id_key ON app.teachers USING btree (stripe_connect_account_id);

CREATE UNIQUE INDEX welcome_cards_pkey ON app.welcome_cards USING btree (id);

CREATE UNIQUE INDEX coupons_pkey ON public.coupons USING btree (code);

CREATE INDEX idx_coupons_expires ON public.coupons USING btree (expires_at);

CREATE INDEX idx_coupons_plan ON public.coupons USING btree (plan_id);

CREATE INDEX idx_public_subscriptions_plan ON public.subscriptions USING btree (plan_id);

CREATE INDEX idx_public_subscriptions_user ON public.subscriptions USING btree (user_id);

CREATE INDEX idx_subscription_plans_active ON public.subscription_plans USING btree (is_active);

CREATE INDEX idx_user_certifications_area ON public.user_certifications USING btree (area);

CREATE UNIQUE INDEX subscription_plans_pkey ON public.subscription_plans USING btree (id);

CREATE UNIQUE INDEX subscriptions_pkey ON public.subscriptions USING btree (id);

CREATE UNIQUE INDEX user_certifications_pkey ON public.user_certifications USING btree (user_id, area);

alter table "app"."activities" add constraint "activities_pkey" PRIMARY KEY using index "activities_pkey";

alter table "app"."app_config" add constraint "app_config_pkey" PRIMARY KEY using index "app_config_pkey";

alter table "app"."auth_events" add constraint "auth_events_pkey" PRIMARY KEY using index "auth_events_pkey";

alter table "app"."billing_logs" add constraint "billing_logs_pkey" PRIMARY KEY using index "billing_logs_pkey";

alter table "app"."certificates" add constraint "certificates_pkey" PRIMARY KEY using index "certificates_pkey";

alter table "app"."classroom_messages" add constraint "classroom_messages_pkey" PRIMARY KEY using index "classroom_messages_pkey";

alter table "app"."classroom_presence" add constraint "classroom_presence_pkey" PRIMARY KEY using index "classroom_presence_pkey";

alter table "app"."course_bundle_courses" add constraint "course_bundle_courses_pkey" PRIMARY KEY using index "course_bundle_courses_pkey";

alter table "app"."course_bundles" add constraint "course_bundles_pkey" PRIMARY KEY using index "course_bundles_pkey";

alter table "app"."course_display_priorities" add constraint "course_display_priorities_pkey" PRIMARY KEY using index "course_display_priorities_pkey";

alter table "app"."course_entitlements" add constraint "course_entitlements_pkey" PRIMARY KEY using index "course_entitlements_pkey";

alter table "app"."course_products" add constraint "course_products_pkey" PRIMARY KEY using index "course_products_pkey";

alter table "app"."course_quizzes" add constraint "course_quizzes_pkey" PRIMARY KEY using index "course_quizzes_pkey";

alter table "app"."courses" add constraint "courses_pkey" PRIMARY KEY using index "courses_pkey";

alter table "app"."enrollments" add constraint "enrollments_pkey" PRIMARY KEY using index "enrollments_pkey";

alter table "app"."entitlements" add constraint "entitlements_pkey" PRIMARY KEY using index "entitlements_pkey";

alter table "app"."event_participants" add constraint "event_participants_pkey" PRIMARY KEY using index "event_participants_pkey";

alter table "app"."events" add constraint "events_pkey" PRIMARY KEY using index "events_pkey";

alter table "app"."follows" add constraint "follows_pkey" PRIMARY KEY using index "follows_pkey";

alter table "app"."guest_claim_tokens" add constraint "guest_claim_tokens_pkey" PRIMARY KEY using index "guest_claim_tokens_pkey";

alter table "app"."home_player_course_links" add constraint "home_player_course_links_pkey" PRIMARY KEY using index "home_player_course_links_pkey";

alter table "app"."home_player_uploads" add constraint "home_player_uploads_pkey" PRIMARY KEY using index "home_player_uploads_pkey";

alter table "app"."intro_usage" add constraint "intro_usage_pkey" PRIMARY KEY using index "intro_usage_pkey";

alter table "app"."lesson_media" add constraint "lesson_media_pkey" PRIMARY KEY using index "lesson_media_pkey";

alter table "app"."lesson_media_issues" add constraint "lesson_media_issues_pkey" PRIMARY KEY using index "lesson_media_issues_pkey";

alter table "app"."lesson_packages" add constraint "lesson_packages_pkey" PRIMARY KEY using index "lesson_packages_pkey";

alter table "app"."lessons" add constraint "lessons_pkey" PRIMARY KEY using index "lessons_pkey";

alter table "app"."live_event_registrations" add constraint "live_event_registrations_pkey" PRIMARY KEY using index "live_event_registrations_pkey";

alter table "app"."live_events" add constraint "live_events_pkey" PRIMARY KEY using index "live_events_pkey";

alter table "app"."livekit_webhook_jobs" add constraint "livekit_webhook_jobs_pkey" PRIMARY KEY using index "livekit_webhook_jobs_pkey";

alter table "app"."media_assets" add constraint "media_assets_pkey" PRIMARY KEY using index "media_assets_pkey";

alter table "app"."media_objects" add constraint "media_objects_pkey" PRIMARY KEY using index "media_objects_pkey";

alter table "app"."media_resolution_failures" add constraint "media_resolution_failures_pkey" PRIMARY KEY using index "media_resolution_failures_pkey";

alter table "app"."meditations" add constraint "meditations_pkey" PRIMARY KEY using index "meditations_pkey";

alter table "app"."memberships" add constraint "memberships_pkey" PRIMARY KEY using index "memberships_pkey";

alter table "app"."messages" add constraint "messages_pkey" PRIMARY KEY using index "messages_pkey";

alter table "app"."music_tracks" add constraint "music_tracks_pkey" PRIMARY KEY using index "music_tracks_pkey";

alter table "app"."notification_audiences" add constraint "notification_audiences_pkey" PRIMARY KEY using index "notification_audiences_pkey";

alter table "app"."notification_campaigns" add constraint "notification_campaigns_pkey" PRIMARY KEY using index "notification_campaigns_pkey";

alter table "app"."notification_deliveries" add constraint "notification_deliveries_pkey" PRIMARY KEY using index "notification_deliveries_pkey";

alter table "app"."notifications" add constraint "notifications_pkey" PRIMARY KEY using index "notifications_pkey";

alter table "app"."orders" add constraint "orders_pkey" PRIMARY KEY using index "orders_pkey";

alter table "app"."payment_events" add constraint "payment_events_pkey" PRIMARY KEY using index "payment_events_pkey";

alter table "app"."payments" add constraint "payments_pkey" PRIMARY KEY using index "payments_pkey";

alter table "app"."posts" add constraint "posts_pkey" PRIMARY KEY using index "posts_pkey";

alter table "app"."profiles" add constraint "profiles_pkey" PRIMARY KEY using index "profiles_pkey";

alter table "app"."purchases" add constraint "purchases_pkey" PRIMARY KEY using index "purchases_pkey";

alter table "app"."quiz_questions" add constraint "quiz_questions_pkey" PRIMARY KEY using index "quiz_questions_pkey";

alter table "app"."referral_codes" add constraint "referral_codes_pkey" PRIMARY KEY using index "referral_codes_pkey";

alter table "app"."refresh_tokens" add constraint "refresh_tokens_pkey" PRIMARY KEY using index "refresh_tokens_pkey";

alter table "app"."reviews" add constraint "reviews_pkey" PRIMARY KEY using index "reviews_pkey";

alter table "app"."runtime_media" add constraint "runtime_media_pkey" PRIMARY KEY using index "runtime_media_pkey";

alter table "app"."seminar_attendees" add constraint "seminar_attendees_pkey" PRIMARY KEY using index "seminar_attendees_pkey";

alter table "app"."seminar_recordings" add constraint "seminar_recordings_pkey" PRIMARY KEY using index "seminar_recordings_pkey";

alter table "app"."seminar_sessions" add constraint "seminar_sessions_pkey" PRIMARY KEY using index "seminar_sessions_pkey";

alter table "app"."seminars" add constraint "seminars_pkey" PRIMARY KEY using index "seminars_pkey";

alter table "app"."services" add constraint "services_pkey" PRIMARY KEY using index "services_pkey";

alter table "app"."session_slots" add constraint "session_slots_pkey" PRIMARY KEY using index "session_slots_pkey";

alter table "app"."sessions" add constraint "sessions_pkey" PRIMARY KEY using index "sessions_pkey";

alter table "app"."stripe_customers" add constraint "stripe_customers_pkey" PRIMARY KEY using index "stripe_customers_pkey";

alter table "app"."subscriptions" add constraint "subscriptions_pkey" PRIMARY KEY using index "subscriptions_pkey";

alter table "app"."tarot_requests" add constraint "tarot_requests_pkey" PRIMARY KEY using index "tarot_requests_pkey";

alter table "app"."teacher_accounts" add constraint "teacher_accounts_pkey" PRIMARY KEY using index "teacher_accounts_pkey";

alter table "app"."teacher_approvals" add constraint "teacher_approvals_pkey" PRIMARY KEY using index "teacher_approvals_pkey";

alter table "app"."teacher_directory" add constraint "teacher_directory_pkey" PRIMARY KEY using index "teacher_directory_pkey";

alter table "app"."teacher_payout_methods" add constraint "teacher_payout_methods_pkey" PRIMARY KEY using index "teacher_payout_methods_pkey";

alter table "app"."teacher_permissions" add constraint "teacher_permissions_pkey" PRIMARY KEY using index "teacher_permissions_pkey";

alter table "app"."teacher_profile_media" add constraint "teacher_profile_media_pkey" PRIMARY KEY using index "teacher_profile_media_pkey";

alter table "app"."teachers" add constraint "teachers_pkey" PRIMARY KEY using index "teachers_pkey";

alter table "app"."welcome_cards" add constraint "welcome_cards_pkey" PRIMARY KEY using index "welcome_cards_pkey";

alter table "public"."coupons" add constraint "coupons_pkey" PRIMARY KEY using index "coupons_pkey";

alter table "public"."subscription_plans" add constraint "subscription_plans_pkey" PRIMARY KEY using index "subscription_plans_pkey";

alter table "public"."subscriptions" add constraint "subscriptions_pkey" PRIMARY KEY using index "subscriptions_pkey";

alter table "public"."user_certifications" add constraint "user_certifications_pkey" PRIMARY KEY using index "user_certifications_pkey";

alter table "app"."activities" add constraint "activities_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL not valid;

alter table "app"."activities" validate constraint "activities_actor_id_fkey";

alter table "app"."auth_events" add constraint "auth_events_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."auth_events" validate constraint "auth_events_user_id_fkey";

alter table "app"."certificates" add constraint "certificates_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE SET NULL not valid;

alter table "app"."certificates" validate constraint "certificates_course_id_fkey";

alter table "app"."certificates" add constraint "certificates_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."certificates" validate constraint "certificates_user_id_fkey";

alter table "app"."classroom_messages" add constraint "classroom_messages_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE not valid;

alter table "app"."classroom_messages" validate constraint "classroom_messages_course_id_fkey";

alter table "app"."classroom_messages" add constraint "classroom_messages_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."classroom_messages" validate constraint "classroom_messages_user_id_fkey";

alter table "app"."classroom_presence" add constraint "classroom_presence_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE not valid;

alter table "app"."classroom_presence" validate constraint "classroom_presence_course_id_fkey";

alter table "app"."classroom_presence" add constraint "classroom_presence_course_id_user_id_key" UNIQUE using index "classroom_presence_course_id_user_id_key";

alter table "app"."classroom_presence" add constraint "classroom_presence_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."classroom_presence" validate constraint "classroom_presence_user_id_fkey";

alter table "app"."course_bundle_courses" add constraint "course_bundle_courses_bundle_id_fkey" FOREIGN KEY (bundle_id) REFERENCES app.course_bundles(id) ON DELETE CASCADE not valid;

alter table "app"."course_bundle_courses" validate constraint "course_bundle_courses_bundle_id_fkey";

alter table "app"."course_bundle_courses" add constraint "course_bundle_courses_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE not valid;

alter table "app"."course_bundle_courses" validate constraint "course_bundle_courses_course_id_fkey";

alter table "app"."course_bundles" add constraint "course_bundles_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."course_bundles" validate constraint "course_bundles_teacher_id_fkey";

alter table "app"."course_display_priorities" add constraint "course_display_priorities_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."course_display_priorities" validate constraint "course_display_priorities_teacher_id_fkey";

alter table "app"."course_display_priorities" add constraint "course_display_priorities_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES app.profiles(user_id) ON DELETE SET NULL not valid;

alter table "app"."course_display_priorities" validate constraint "course_display_priorities_updated_by_fkey";

alter table "app"."course_entitlements" add constraint "course_entitlements_user_course_key" UNIQUE using index "course_entitlements_user_course_key";

alter table "app"."course_entitlements" add constraint "course_entitlements_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "app"."course_entitlements" validate constraint "course_entitlements_user_id_fkey";

alter table "app"."course_products" add constraint "course_products_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE not valid;

alter table "app"."course_products" validate constraint "course_products_course_id_fkey";

alter table "app"."course_products" add constraint "course_products_course_id_key" UNIQUE using index "course_products_course_id_key";

alter table "app"."course_quizzes" add constraint "course_quizzes_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE not valid;

alter table "app"."course_quizzes" validate constraint "course_quizzes_course_id_fkey";

alter table "app"."course_quizzes" add constraint "course_quizzes_created_by_fkey" FOREIGN KEY (created_by) REFERENCES app.profiles(user_id) ON DELETE SET NULL not valid;

alter table "app"."course_quizzes" validate constraint "course_quizzes_created_by_fkey";

alter table "app"."courses" add constraint "courses_cover_media_id_fkey" FOREIGN KEY (cover_media_id) REFERENCES app.media_assets(id) ON DELETE SET NULL not valid;

alter table "app"."courses" validate constraint "courses_cover_media_id_fkey";

alter table "app"."courses" add constraint "courses_created_by_fkey" FOREIGN KEY (created_by) REFERENCES app.profiles(user_id) ON DELETE SET NULL not valid;

alter table "app"."courses" validate constraint "courses_created_by_fkey";

alter table "app"."courses" add constraint "courses_journey_step_check" CHECK ((journey_step = ANY (ARRAY['intro'::text, 'step1'::text, 'step2'::text, 'step3'::text]))) not valid;

alter table "app"."courses" validate constraint "courses_journey_step_check";

alter table "app"."courses" add constraint "courses_slug_key" UNIQUE using index "courses_slug_key";

alter table "app"."enrollments" add constraint "enrollments_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE not valid;

alter table "app"."enrollments" validate constraint "enrollments_course_id_fkey";

alter table "app"."enrollments" add constraint "enrollments_user_id_course_id_key" UNIQUE using index "enrollments_user_id_course_id_key";

alter table "app"."enrollments" add constraint "enrollments_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."enrollments" validate constraint "enrollments_user_id_fkey";

alter table "app"."entitlements" add constraint "entitlements_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE not valid;

alter table "app"."entitlements" validate constraint "entitlements_course_id_fkey";

alter table "app"."entitlements" add constraint "entitlements_source_check" CHECK ((source = ANY (ARRAY['purchase'::text, 'subscription'::text, 'admin'::text]))) not valid;

alter table "app"."entitlements" validate constraint "entitlements_source_check";

alter table "app"."entitlements" add constraint "entitlements_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."entitlements" validate constraint "entitlements_user_id_fkey";

alter table "app"."event_participants" add constraint "event_participants_event_id_fkey" FOREIGN KEY (event_id) REFERENCES app.events(id) ON DELETE CASCADE not valid;

alter table "app"."event_participants" validate constraint "event_participants_event_id_fkey";

alter table "app"."event_participants" add constraint "event_participants_event_id_user_id_key" UNIQUE using index "event_participants_event_id_user_id_key";

alter table "app"."event_participants" add constraint "event_participants_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."event_participants" validate constraint "event_participants_user_id_fkey";

alter table "app"."events" add constraint "events_created_by_fkey" FOREIGN KEY (created_by) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."events" validate constraint "events_created_by_fkey";

alter table "app"."events" add constraint "events_end_after_start" CHECK ((end_at > start_at)) not valid;

alter table "app"."events" validate constraint "events_end_after_start";

alter table "app"."events" add constraint "events_image_id_fkey" FOREIGN KEY (image_id) REFERENCES app.media_objects(id) ON DELETE SET NULL not valid;

alter table "app"."events" validate constraint "events_image_id_fkey";

alter table "app"."events" add constraint "events_timezone_not_empty" CHECK ((length(TRIM(BOTH FROM timezone)) > 0)) not valid;

alter table "app"."events" validate constraint "events_timezone_not_empty";

alter table "app"."events" add constraint "events_title_not_empty" CHECK ((length(TRIM(BOTH FROM title)) > 0)) not valid;

alter table "app"."events" validate constraint "events_title_not_empty";

alter table "app"."follows" add constraint "follows_followee_id_fkey" FOREIGN KEY (followee_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."follows" validate constraint "follows_followee_id_fkey";

alter table "app"."follows" add constraint "follows_follower_id_fkey" FOREIGN KEY (follower_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."follows" validate constraint "follows_follower_id_fkey";

alter table "app"."guest_claim_tokens" add constraint "guest_claim_tokens_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE SET NULL not valid;

alter table "app"."guest_claim_tokens" validate constraint "guest_claim_tokens_course_id_fkey";

alter table "app"."guest_claim_tokens" add constraint "guest_claim_tokens_purchase_id_fkey" FOREIGN KEY (purchase_id) REFERENCES app.purchases(id) ON DELETE CASCADE not valid;

alter table "app"."guest_claim_tokens" validate constraint "guest_claim_tokens_purchase_id_fkey";

alter table "app"."guest_claim_tokens" add constraint "guest_claim_tokens_token_key" UNIQUE using index "guest_claim_tokens_token_key";

alter table "app"."home_player_course_links" add constraint "home_player_course_links_lesson_media_id_fkey" FOREIGN KEY (lesson_media_id) REFERENCES app.lesson_media(id) ON DELETE SET NULL not valid;

alter table "app"."home_player_course_links" validate constraint "home_player_course_links_lesson_media_id_fkey";

alter table "app"."home_player_course_links" add constraint "home_player_course_links_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."home_player_course_links" validate constraint "home_player_course_links_teacher_id_fkey";

alter table "app"."home_player_course_links" add constraint "home_player_course_links_teacher_id_lesson_media_id_key" UNIQUE using index "home_player_course_links_teacher_id_lesson_media_id_key";

alter table "app"."home_player_uploads" add constraint "home_player_uploads_kind_check" CHECK ((kind = ANY (ARRAY['audio'::text, 'video'::text]))) not valid;

alter table "app"."home_player_uploads" validate constraint "home_player_uploads_kind_check";

alter table "app"."home_player_uploads" add constraint "home_player_uploads_media_asset_id_fkey" FOREIGN KEY (media_asset_id) REFERENCES app.media_assets(id) not valid;

alter table "app"."home_player_uploads" validate constraint "home_player_uploads_media_asset_id_fkey";

alter table "app"."home_player_uploads" add constraint "home_player_uploads_media_id_fkey" FOREIGN KEY (media_id) REFERENCES app.media_objects(id) not valid;

alter table "app"."home_player_uploads" validate constraint "home_player_uploads_media_id_fkey";

alter table "app"."home_player_uploads" add constraint "home_player_uploads_media_ref_check" CHECK (((media_id IS NULL) <> (media_asset_id IS NULL))) not valid;

alter table "app"."home_player_uploads" validate constraint "home_player_uploads_media_ref_check";

alter table "app"."home_player_uploads" add constraint "home_player_uploads_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."home_player_uploads" validate constraint "home_player_uploads_teacher_id_fkey";

alter table "app"."intro_usage" add constraint "intro_usage_count_check" CHECK ((count >= 0)) not valid;

alter table "app"."intro_usage" validate constraint "intro_usage_count_check";

alter table "app"."intro_usage" add constraint "intro_usage_month_check" CHECK (((month >= 1) AND (month <= 12))) not valid;

alter table "app"."intro_usage" validate constraint "intro_usage_month_check";

alter table "app"."intro_usage" add constraint "intro_usage_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "app"."intro_usage" validate constraint "intro_usage_user_id_fkey";

alter table "app"."intro_usage" add constraint "intro_usage_year_check" CHECK (((year >= 2000) AND (year <= 9999))) not valid;

alter table "app"."intro_usage" validate constraint "intro_usage_year_check";

alter table "app"."lesson_media" add constraint "lesson_media_kind_check" CHECK ((kind = ANY (ARRAY['video'::text, 'audio'::text, 'image'::text, 'pdf'::text, 'other'::text]))) not valid;

alter table "app"."lesson_media" validate constraint "lesson_media_kind_check";

alter table "app"."lesson_media" add constraint "lesson_media_lesson_id_fkey" FOREIGN KEY (lesson_id) REFERENCES app.lessons(id) ON DELETE CASCADE not valid;

alter table "app"."lesson_media" validate constraint "lesson_media_lesson_id_fkey";

alter table "app"."lesson_media" add constraint "lesson_media_lesson_id_position_key" UNIQUE using index "lesson_media_lesson_id_position_key";

alter table "app"."lesson_media" add constraint "lesson_media_media_asset_id_fkey" FOREIGN KEY (media_asset_id) REFERENCES app.media_assets(id) ON DELETE SET NULL not valid;

alter table "app"."lesson_media" validate constraint "lesson_media_media_asset_id_fkey";

alter table "app"."lesson_media" add constraint "lesson_media_media_id_fkey" FOREIGN KEY (media_id) REFERENCES app.media_objects(id) ON DELETE SET NULL not valid;

alter table "app"."lesson_media" validate constraint "lesson_media_media_id_fkey";

alter table "app"."lesson_media" add constraint "lesson_media_path_or_object" CHECK (((media_id IS NOT NULL) OR (storage_path IS NOT NULL) OR (media_asset_id IS NOT NULL))) not valid;

alter table "app"."lesson_media" validate constraint "lesson_media_path_or_object";

alter table "app"."lesson_media_issues" add constraint "lesson_media_issues_issue_check" CHECK ((issue = ANY (ARRAY['missing_object'::text, 'bucket_mismatch'::text, 'key_format_drift'::text, 'unsupported'::text]))) not valid;

alter table "app"."lesson_media_issues" validate constraint "lesson_media_issues_issue_check";

alter table "app"."lesson_media_issues" add constraint "lesson_media_issues_lesson_media_id_fkey" FOREIGN KEY (lesson_media_id) REFERENCES app.lesson_media(id) ON DELETE CASCADE not valid;

alter table "app"."lesson_media_issues" validate constraint "lesson_media_issues_lesson_media_id_fkey";

alter table "app"."lesson_packages" add constraint "lesson_packages_lesson_id_fkey" FOREIGN KEY (lesson_id) REFERENCES app.lessons(id) ON DELETE CASCADE not valid;

alter table "app"."lesson_packages" validate constraint "lesson_packages_lesson_id_fkey";

alter table "app"."lesson_packages" add constraint "lesson_packages_lesson_id_key" UNIQUE using index "lesson_packages_lesson_id_key";

alter table "app"."lessons" add constraint "lessons_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE not valid;

alter table "app"."lessons" validate constraint "lessons_course_id_fkey";

alter table "app"."lessons" add constraint "lessons_course_id_position_key" UNIQUE using index "lessons_course_id_position_key";

alter table "app"."live_event_registrations" add constraint "live_event_registrations_event_id_fkey" FOREIGN KEY (event_id) REFERENCES app.live_events(id) ON DELETE CASCADE not valid;

alter table "app"."live_event_registrations" validate constraint "live_event_registrations_event_id_fkey";

alter table "app"."live_event_registrations" add constraint "live_event_registrations_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."live_event_registrations" validate constraint "live_event_registrations_user_id_fkey";

alter table "app"."live_events" add constraint "live_events_access_type_check" CHECK ((access_type = ANY (ARRAY['membership'::text, 'course'::text]))) not valid;

alter table "app"."live_events" validate constraint "live_events_access_type_check";

alter table "app"."live_events" add constraint "live_events_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) not valid;

alter table "app"."live_events" validate constraint "live_events_course_id_fkey";

alter table "app"."live_events" add constraint "live_events_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."live_events" validate constraint "live_events_teacher_id_fkey";

alter table "app"."media_assets" add constraint "media_assets_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE SET NULL not valid;

alter table "app"."media_assets" validate constraint "media_assets_course_id_fkey";

alter table "app"."media_assets" add constraint "media_assets_lesson_id_fkey" FOREIGN KEY (lesson_id) REFERENCES app.lessons(id) ON DELETE SET NULL not valid;

alter table "app"."media_assets" validate constraint "media_assets_lesson_id_fkey";

alter table "app"."media_assets" add constraint "media_assets_media_type_check" CHECK ((media_type = ANY (ARRAY['audio'::text, 'document'::text, 'image'::text, 'video'::text]))) not valid;

alter table "app"."media_assets" validate constraint "media_assets_media_type_check";

alter table "app"."media_assets" add constraint "media_assets_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL not valid;

alter table "app"."media_assets" validate constraint "media_assets_owner_id_fkey";

alter table "app"."media_assets" add constraint "media_assets_purpose_check" CHECK ((purpose = ANY (ARRAY['lesson_audio'::text, 'course_cover'::text, 'home_player_audio'::text, 'lesson_media'::text]))) not valid;

alter table "app"."media_assets" validate constraint "media_assets_purpose_check";

alter table "app"."media_assets" add constraint "media_assets_state_check" CHECK ((state = ANY (ARRAY['pending_upload'::text, 'uploaded'::text, 'processing'::text, 'ready'::text, 'failed'::text]))) not valid;

alter table "app"."media_assets" validate constraint "media_assets_state_check";

alter table "app"."media_objects" add constraint "media_objects_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL not valid;

alter table "app"."media_objects" validate constraint "media_objects_owner_id_fkey";

alter table "app"."media_objects" add constraint "media_objects_storage_path_storage_bucket_key" UNIQUE using index "media_objects_storage_path_storage_bucket_key";

alter table "app"."media_resolution_failures" add constraint "media_resolution_failures_lesson_media_id_fkey" FOREIGN KEY (lesson_media_id) REFERENCES app.lesson_media(id) ON DELETE SET NULL not valid;

alter table "app"."media_resolution_failures" validate constraint "media_resolution_failures_lesson_media_id_fkey";

alter table "app"."meditations" add constraint "meditations_created_by_fkey" FOREIGN KEY (created_by) REFERENCES app.profiles(user_id) ON DELETE SET NULL not valid;

alter table "app"."meditations" validate constraint "meditations_created_by_fkey";

alter table "app"."meditations" add constraint "meditations_media_id_fkey" FOREIGN KEY (media_id) REFERENCES app.media_objects(id) ON DELETE SET NULL not valid;

alter table "app"."meditations" validate constraint "meditations_media_id_fkey";

alter table "app"."meditations" add constraint "meditations_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."meditations" validate constraint "meditations_teacher_id_fkey";

alter table "app"."memberships" add constraint "memberships_plan_interval_check" CHECK ((plan_interval = ANY (ARRAY['month'::text, 'year'::text]))) not valid;

alter table "app"."memberships" validate constraint "memberships_plan_interval_check";

alter table "app"."memberships" add constraint "memberships_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "app"."memberships" validate constraint "memberships_user_id_fkey";

alter table "app"."memberships" add constraint "memberships_user_id_key" UNIQUE using index "memberships_user_id_key";

alter table "app"."messages" add constraint "messages_recipient_id_fkey" FOREIGN KEY (recipient_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL not valid;

alter table "app"."messages" validate constraint "messages_recipient_id_fkey";

alter table "app"."messages" add constraint "messages_sender_id_fkey" FOREIGN KEY (sender_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL not valid;

alter table "app"."messages" validate constraint "messages_sender_id_fkey";

alter table "app"."music_tracks" add constraint "music_tracks_access_scope_check" CHECK ((access_scope = ANY (ARRAY['membership'::text, 'course'::text]))) not valid;

alter table "app"."music_tracks" validate constraint "music_tracks_access_scope_check";

alter table "app"."music_tracks" add constraint "music_tracks_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE not valid;

alter table "app"."music_tracks" validate constraint "music_tracks_course_id_fkey";

alter table "app"."music_tracks" add constraint "music_tracks_scope_course" CHECK ((((access_scope = 'course'::text) AND (course_id IS NOT NULL)) OR ((access_scope = 'membership'::text) AND (course_id IS NULL)))) not valid;

alter table "app"."music_tracks" validate constraint "music_tracks_scope_course";

alter table "app"."music_tracks" add constraint "music_tracks_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."music_tracks" validate constraint "music_tracks_teacher_id_fkey";

alter table "app"."notification_audiences" add constraint "notification_audiences_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE not valid;

alter table "app"."notification_audiences" validate constraint "notification_audiences_course_id_fkey";

alter table "app"."notification_audiences" add constraint "notification_audiences_event_id_fkey" FOREIGN KEY (event_id) REFERENCES app.events(id) ON DELETE CASCADE not valid;

alter table "app"."notification_audiences" validate constraint "notification_audiences_event_id_fkey";

alter table "app"."notification_audiences" add constraint "notification_audiences_notification_id_fkey" FOREIGN KEY (notification_id) REFERENCES app.notification_campaigns(id) ON DELETE CASCADE not valid;

alter table "app"."notification_audiences" validate constraint "notification_audiences_notification_id_fkey";

alter table "app"."notification_audiences" add constraint "notification_audiences_target_check" CHECK ((((audience_type = 'all_members'::app.notification_audience_type) AND (event_id IS NULL) AND (course_id IS NULL)) OR ((audience_type = 'event_participants'::app.notification_audience_type) AND (event_id IS NOT NULL) AND (course_id IS NULL)) OR ((audience_type = ANY (ARRAY['course_participants'::app.notification_audience_type, 'course_members'::app.notification_audience_type])) AND (course_id IS NOT NULL) AND (event_id IS NULL)))) not valid;

alter table "app"."notification_audiences" validate constraint "notification_audiences_target_check";

alter table "app"."notification_campaigns" add constraint "notification_campaigns_body_not_empty" CHECK ((length(TRIM(BOTH FROM body)) > 0)) not valid;

alter table "app"."notification_campaigns" validate constraint "notification_campaigns_body_not_empty";

alter table "app"."notification_campaigns" add constraint "notification_campaigns_created_by_fkey" FOREIGN KEY (created_by) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."notification_campaigns" validate constraint "notification_campaigns_created_by_fkey";

alter table "app"."notification_campaigns" add constraint "notification_campaigns_title_not_empty" CHECK ((length(TRIM(BOTH FROM title)) > 0)) not valid;

alter table "app"."notification_campaigns" validate constraint "notification_campaigns_title_not_empty";

alter table "app"."notification_deliveries" add constraint "notification_deliveries_notification_id_fkey" FOREIGN KEY (notification_id) REFERENCES app.notification_campaigns(id) ON DELETE CASCADE not valid;

alter table "app"."notification_deliveries" validate constraint "notification_deliveries_notification_id_fkey";

alter table "app"."notification_deliveries" add constraint "notification_deliveries_notification_id_user_id_channel_key" UNIQUE using index "notification_deliveries_notification_id_user_id_channel_key";

alter table "app"."notification_deliveries" add constraint "notification_deliveries_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."notification_deliveries" validate constraint "notification_deliveries_user_id_fkey";

alter table "app"."notifications" add constraint "notifications_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."notifications" validate constraint "notifications_user_id_fkey";

alter table "app"."orders" add constraint "orders_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE SET NULL not valid;

alter table "app"."orders" validate constraint "orders_course_id_fkey";

alter table "app"."orders" add constraint "orders_service_id_fkey" FOREIGN KEY (service_id) REFERENCES app.services(id) ON DELETE SET NULL not valid;

alter table "app"."orders" validate constraint "orders_service_id_fkey";

alter table "app"."orders" add constraint "orders_session_id_fkey" FOREIGN KEY (session_id) REFERENCES app.sessions(id) ON DELETE SET NULL not valid;

alter table "app"."orders" validate constraint "orders_session_id_fkey";

alter table "app"."orders" add constraint "orders_session_slot_id_fkey" FOREIGN KEY (session_slot_id) REFERENCES app.session_slots(id) ON DELETE SET NULL not valid;

alter table "app"."orders" validate constraint "orders_session_slot_id_fkey";

alter table "app"."orders" add constraint "orders_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."orders" validate constraint "orders_user_id_fkey";

alter table "app"."payment_events" add constraint "payment_events_event_id_key" UNIQUE using index "payment_events_event_id_key";

alter table "app"."payments" add constraint "payments_order_id_fkey" FOREIGN KEY (order_id) REFERENCES app.orders(id) ON DELETE CASCADE not valid;

alter table "app"."payments" validate constraint "payments_order_id_fkey";

alter table "app"."posts" add constraint "posts_author_id_fkey" FOREIGN KEY (author_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."posts" validate constraint "posts_author_id_fkey";

alter table "app"."profiles" add constraint "profiles_avatar_media_id_fkey" FOREIGN KEY (avatar_media_id) REFERENCES app.media_objects(id) not valid;

alter table "app"."profiles" validate constraint "profiles_avatar_media_id_fkey";

alter table "app"."profiles" add constraint "profiles_email_key" UNIQUE using index "profiles_email_key";

alter table "app"."profiles" add constraint "profiles_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "app"."profiles" validate constraint "profiles_user_id_fkey";

alter table "app"."purchases" add constraint "purchases_order_id_fkey" FOREIGN KEY (order_id) REFERENCES app.orders(id) ON DELETE SET NULL not valid;

alter table "app"."purchases" validate constraint "purchases_order_id_fkey";

alter table "app"."purchases" add constraint "purchases_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."purchases" validate constraint "purchases_user_id_fkey";

alter table "app"."quiz_questions" add constraint "quiz_questions_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE not valid;

alter table "app"."quiz_questions" validate constraint "quiz_questions_course_id_fkey";

alter table "app"."quiz_questions" add constraint "quiz_questions_quiz_id_fkey" FOREIGN KEY (quiz_id) REFERENCES app.course_quizzes(id) ON DELETE CASCADE not valid;

alter table "app"."quiz_questions" validate constraint "quiz_questions_quiz_id_fkey";

alter table "app"."referral_codes" add constraint "referral_codes_code_key" UNIQUE using index "referral_codes_code_key";

alter table "app"."refresh_tokens" add constraint "refresh_tokens_jti_key" UNIQUE using index "refresh_tokens_jti_key";

alter table "app"."refresh_tokens" add constraint "refresh_tokens_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."refresh_tokens" validate constraint "refresh_tokens_user_id_fkey";

alter table "app"."reviews" add constraint "reviews_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE not valid;

alter table "app"."reviews" validate constraint "reviews_course_id_fkey";

alter table "app"."reviews" add constraint "reviews_order_id_fkey" FOREIGN KEY (order_id) REFERENCES app.orders(id) ON DELETE SET NULL not valid;

alter table "app"."reviews" validate constraint "reviews_order_id_fkey";

alter table "app"."reviews" add constraint "reviews_rating_check" CHECK (((rating >= 1) AND (rating <= 5))) not valid;

alter table "app"."reviews" validate constraint "reviews_rating_check";

alter table "app"."reviews" add constraint "reviews_reviewer_id_fkey" FOREIGN KEY (reviewer_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."reviews" validate constraint "reviews_reviewer_id_fkey";

alter table "app"."reviews" add constraint "reviews_service_id_fkey" FOREIGN KEY (service_id) REFERENCES app.services(id) ON DELETE CASCADE not valid;

alter table "app"."reviews" validate constraint "reviews_service_id_fkey";

alter table "app"."runtime_media" add constraint "runtime_media_auth_scope_check" CHECK ((auth_scope = ANY (ARRAY['lesson_course'::text, 'home_teacher_library'::text]))) not valid;

alter table "app"."runtime_media" validate constraint "runtime_media_auth_scope_check";

alter table "app"."runtime_media" add constraint "runtime_media_auth_shape" CHECK ((((auth_scope = 'lesson_course'::text) AND (lesson_media_id IS NOT NULL) AND (course_id IS NOT NULL) AND (lesson_id IS NOT NULL)) OR ((auth_scope = 'home_teacher_library'::text) AND (home_player_upload_id IS NOT NULL)))) not valid;

alter table "app"."runtime_media" validate constraint "runtime_media_auth_shape";

alter table "app"."runtime_media" add constraint "runtime_media_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE SET NULL not valid;

alter table "app"."runtime_media" validate constraint "runtime_media_course_id_fkey";

alter table "app"."runtime_media" add constraint "runtime_media_fallback_policy_check" CHECK ((fallback_policy = ANY (ARRAY['never'::text, 'if_no_ready_asset'::text, 'legacy_only'::text]))) not valid;

alter table "app"."runtime_media" validate constraint "runtime_media_fallback_policy_check";

alter table "app"."runtime_media" add constraint "runtime_media_home_player_upload_id_fkey" FOREIGN KEY (home_player_upload_id) REFERENCES app.home_player_uploads(id) ON DELETE CASCADE not valid;

alter table "app"."runtime_media" validate constraint "runtime_media_home_player_upload_id_fkey";

alter table "app"."runtime_media" add constraint "runtime_media_home_player_upload_id_key" UNIQUE using index "runtime_media_home_player_upload_id_key";

alter table "app"."runtime_media" add constraint "runtime_media_kind_check" CHECK ((kind = ANY (ARRAY['audio'::text, 'video'::text, 'image'::text, 'document'::text, 'other'::text]))) not valid;

alter table "app"."runtime_media" validate constraint "runtime_media_kind_check";

alter table "app"."runtime_media" add constraint "runtime_media_legacy_storage_pair" CHECK (((legacy_storage_path IS NULL) OR (legacy_storage_bucket IS NOT NULL))) not valid;

alter table "app"."runtime_media" validate constraint "runtime_media_legacy_storage_pair";

alter table "app"."runtime_media" add constraint "runtime_media_lesson_id_fkey" FOREIGN KEY (lesson_id) REFERENCES app.lessons(id) ON DELETE SET NULL not valid;

alter table "app"."runtime_media" validate constraint "runtime_media_lesson_id_fkey";

alter table "app"."runtime_media" add constraint "runtime_media_lesson_media_id_fkey" FOREIGN KEY (lesson_media_id) REFERENCES app.lesson_media(id) ON DELETE CASCADE not valid;

alter table "app"."runtime_media" validate constraint "runtime_media_lesson_media_id_fkey";

alter table "app"."runtime_media" add constraint "runtime_media_lesson_media_id_key" UNIQUE using index "runtime_media_lesson_media_id_key";

alter table "app"."runtime_media" add constraint "runtime_media_media_asset_id_fkey" FOREIGN KEY (media_asset_id) REFERENCES app.media_assets(id) ON DELETE SET NULL not valid;

alter table "app"."runtime_media" validate constraint "runtime_media_media_asset_id_fkey";

alter table "app"."runtime_media" add constraint "runtime_media_media_object_id_fkey" FOREIGN KEY (media_object_id) REFERENCES app.media_objects(id) ON DELETE SET NULL not valid;

alter table "app"."runtime_media" validate constraint "runtime_media_media_object_id_fkey";

alter table "app"."runtime_media" add constraint "runtime_media_one_origin" CHECK (((((lesson_media_id IS NOT NULL))::integer + ((home_player_upload_id IS NOT NULL))::integer) = 1)) not valid;

alter table "app"."runtime_media" validate constraint "runtime_media_one_origin";

alter table "app"."runtime_media" add constraint "runtime_media_reference_type_check" CHECK ((reference_type = ANY (ARRAY['lesson_media'::text, 'home_player_upload'::text]))) not valid;

alter table "app"."runtime_media" validate constraint "runtime_media_reference_type_check";

alter table "app"."runtime_media" add constraint "runtime_media_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL not valid;

alter table "app"."runtime_media" validate constraint "runtime_media_teacher_id_fkey";

alter table "app"."seminar_attendees" add constraint "seminar_attendees_seminar_id_fkey" FOREIGN KEY (seminar_id) REFERENCES app.seminars(id) ON DELETE CASCADE not valid;

alter table "app"."seminar_attendees" validate constraint "seminar_attendees_seminar_id_fkey";

alter table "app"."seminar_attendees" add constraint "seminar_attendees_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."seminar_attendees" validate constraint "seminar_attendees_user_id_fkey";

alter table "app"."seminar_recordings" add constraint "seminar_recordings_seminar_id_fkey" FOREIGN KEY (seminar_id) REFERENCES app.seminars(id) ON DELETE CASCADE not valid;

alter table "app"."seminar_recordings" validate constraint "seminar_recordings_seminar_id_fkey";

alter table "app"."seminar_recordings" add constraint "seminar_recordings_session_id_fkey" FOREIGN KEY (session_id) REFERENCES app.seminar_sessions(id) ON DELETE SET NULL not valid;

alter table "app"."seminar_recordings" validate constraint "seminar_recordings_session_id_fkey";

alter table "app"."seminar_sessions" add constraint "seminar_sessions_seminar_id_fkey" FOREIGN KEY (seminar_id) REFERENCES app.seminars(id) ON DELETE CASCADE not valid;

alter table "app"."seminar_sessions" validate constraint "seminar_sessions_seminar_id_fkey";

alter table "app"."seminars" add constraint "seminars_host_id_fkey" FOREIGN KEY (host_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."seminars" validate constraint "seminars_host_id_fkey";

alter table "app"."services" add constraint "services_provider_id_fkey" FOREIGN KEY (provider_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."services" validate constraint "services_provider_id_fkey";

alter table "app"."session_slots" add constraint "session_slots_seats_taken_check" CHECK ((seats_taken >= 0)) not valid;

alter table "app"."session_slots" validate constraint "session_slots_seats_taken_check";

alter table "app"."session_slots" add constraint "session_slots_seats_total_check" CHECK ((seats_total >= 0)) not valid;

alter table "app"."session_slots" validate constraint "session_slots_seats_total_check";

alter table "app"."session_slots" add constraint "session_slots_session_id_fkey" FOREIGN KEY (session_id) REFERENCES app.sessions(id) ON DELETE CASCADE not valid;

alter table "app"."session_slots" validate constraint "session_slots_session_id_fkey";

alter table "app"."session_slots" add constraint "session_slots_session_id_start_at_key" UNIQUE using index "session_slots_session_id_start_at_key";

alter table "app"."sessions" add constraint "sessions_capacity_check" CHECK (((capacity IS NULL) OR (capacity >= 0))) not valid;

alter table "app"."sessions" validate constraint "sessions_capacity_check";

alter table "app"."sessions" add constraint "sessions_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."sessions" validate constraint "sessions_teacher_id_fkey";

alter table "app"."stripe_customers" add constraint "stripe_customers_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."stripe_customers" validate constraint "stripe_customers_user_id_fkey";

alter table "app"."subscriptions" add constraint "subscriptions_subscription_id_key" UNIQUE using index "subscriptions_subscription_id_key";

alter table "app"."subscriptions" add constraint "subscriptions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "app"."subscriptions" validate constraint "subscriptions_user_id_fkey";

alter table "app"."tarot_requests" add constraint "tarot_requests_requester_id_fkey" FOREIGN KEY (requester_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."tarot_requests" validate constraint "tarot_requests_requester_id_fkey";

alter table "app"."teacher_accounts" add constraint "teacher_accounts_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."teacher_accounts" validate constraint "teacher_accounts_user_id_fkey";

alter table "app"."teacher_approvals" add constraint "teacher_approvals_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES app.profiles(user_id) not valid;

alter table "app"."teacher_approvals" validate constraint "teacher_approvals_approved_by_fkey";

alter table "app"."teacher_approvals" add constraint "teacher_approvals_reviewer_id_fkey" FOREIGN KEY (reviewer_id) REFERENCES app.profiles(user_id) not valid;

alter table "app"."teacher_approvals" validate constraint "teacher_approvals_reviewer_id_fkey";

alter table "app"."teacher_approvals" add constraint "teacher_approvals_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."teacher_approvals" validate constraint "teacher_approvals_user_id_fkey";

alter table "app"."teacher_approvals" add constraint "teacher_approvals_user_id_key" UNIQUE using index "teacher_approvals_user_id_key";

alter table "app"."teacher_directory" add constraint "teacher_directory_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."teacher_directory" validate constraint "teacher_directory_user_id_fkey";

alter table "app"."teacher_payout_methods" add constraint "teacher_payout_methods_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."teacher_payout_methods" validate constraint "teacher_payout_methods_teacher_id_fkey";

alter table "app"."teacher_payout_methods" add constraint "teacher_payout_methods_teacher_id_provider_reference_key" UNIQUE using index "teacher_payout_methods_teacher_id_provider_reference_key";

alter table "app"."teacher_permissions" add constraint "teacher_permissions_granted_by_fkey" FOREIGN KEY (granted_by) REFERENCES app.profiles(user_id) not valid;

alter table "app"."teacher_permissions" validate constraint "teacher_permissions_granted_by_fkey";

alter table "app"."teacher_permissions" add constraint "teacher_permissions_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."teacher_permissions" validate constraint "teacher_permissions_profile_id_fkey";

alter table "app"."teacher_profile_media" add constraint "teacher_profile_media_cover_media_id_fkey" FOREIGN KEY (cover_media_id) REFERENCES app.media_objects(id) ON DELETE SET NULL not valid;

alter table "app"."teacher_profile_media" validate constraint "teacher_profile_media_cover_media_id_fkey";

alter table "app"."teacher_profile_media" add constraint "teacher_profile_media_media_id_fkey" FOREIGN KEY (media_id) REFERENCES app.lesson_media(id) ON DELETE SET NULL not valid;

alter table "app"."teacher_profile_media" validate constraint "teacher_profile_media_media_id_fkey";

alter table "app"."teacher_profile_media" add constraint "teacher_profile_media_media_kind_check" CHECK ((media_kind = ANY (ARRAY['lesson_media'::text, 'seminar_recording'::text, 'external'::text]))) not valid;

alter table "app"."teacher_profile_media" validate constraint "teacher_profile_media_media_kind_check";

alter table "app"."teacher_profile_media" add constraint "teacher_profile_media_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."teacher_profile_media" validate constraint "teacher_profile_media_teacher_id_fkey";

alter table "app"."teacher_profile_media" add constraint "teacher_profile_media_teacher_id_media_kind_media_id_key" UNIQUE using index "teacher_profile_media_teacher_id_media_kind_media_id_key";

alter table "app"."teachers" add constraint "teachers_payout_split_pct_check" CHECK (((payout_split_pct >= 0) AND (payout_split_pct <= 100))) not valid;

alter table "app"."teachers" validate constraint "teachers_payout_split_pct_check";

alter table "app"."teachers" add constraint "teachers_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."teachers" validate constraint "teachers_profile_id_fkey";

alter table "app"."teachers" add constraint "teachers_profile_id_key" UNIQUE using index "teachers_profile_id_key";

alter table "app"."teachers" add constraint "teachers_stripe_connect_account_id_key" UNIQUE using index "teachers_stripe_connect_account_id_key";

alter table "app"."welcome_cards" add constraint "welcome_cards_created_by_fkey" FOREIGN KEY (created_by) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."welcome_cards" validate constraint "welcome_cards_created_by_fkey";

alter table "app"."welcome_cards" add constraint "welcome_cards_day_check" CHECK (((day >= 1) AND (day <= 31))) not valid;

alter table "app"."welcome_cards" validate constraint "welcome_cards_day_check";

alter table "app"."welcome_cards" add constraint "welcome_cards_day_month_pair" CHECK ((((day IS NULL) AND (month IS NULL)) OR ((day IS NOT NULL) AND (month IS NOT NULL)))) not valid;

alter table "app"."welcome_cards" validate constraint "welcome_cards_day_month_pair";

alter table "app"."welcome_cards" add constraint "welcome_cards_month_check" CHECK (((month >= 1) AND (month <= 12))) not valid;

alter table "app"."welcome_cards" validate constraint "welcome_cards_month_check";

alter table "public"."coupons" add constraint "coupons_plan_id_fkey" FOREIGN KEY (plan_id) REFERENCES public.subscription_plans(id) ON DELETE SET NULL not valid;

alter table "public"."coupons" validate constraint "coupons_plan_id_fkey";

alter table "public"."subscription_plans" add constraint "subscription_plans_interval_check" CHECK (("interval" = ANY (ARRAY['month'::text, 'year'::text]))) not valid;

alter table "public"."subscription_plans" validate constraint "subscription_plans_interval_check";

alter table "public"."subscriptions" add constraint "subscriptions_plan_id_fkey" FOREIGN KEY (plan_id) REFERENCES public.subscription_plans(id) ON DELETE RESTRICT not valid;

alter table "public"."subscriptions" validate constraint "subscriptions_plan_id_fkey";

alter table "public"."subscriptions" add constraint "subscriptions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."subscriptions" validate constraint "subscriptions_user_id_fkey";

alter table "public"."user_certifications" add constraint "user_certifications_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."user_certifications" validate constraint "user_certifications_user_id_fkey";

set check_function_bodies = off;

create or replace view "app"."activities_feed" as  SELECT id,
    activity_type,
    actor_id,
    subject_table,
    subject_id,
    summary,
    metadata,
    occurred_at
   FROM app.activities a;


CREATE OR REPLACE FUNCTION app.can_access_seminar(p_seminar_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select app.can_access_seminar(p_seminar_id, auth.uid());
$function$
;

CREATE OR REPLACE FUNCTION app.can_access_seminar(p_seminar_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select
    app.is_seminar_host(p_seminar_id, p_user_id)
    or app.is_seminar_attendee(p_seminar_id, p_user_id);
$function$
;

create or replace view "app"."course_enrollments_view" as  SELECT e.user_id,
    e.course_id,
    c.title AS course_title,
    e.source AS purchase_source,
    e.created_at
   FROM (app.entitlements e
     JOIN app.courses c ON ((c.id = e.course_id)));


CREATE OR REPLACE FUNCTION app.enforce_event_status_progression()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  old_rank integer;
  new_rank integer;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.status = new.status then
    return new;
  end if;

  if old.status = 'cancelled' then
    raise exception 'Event status cannot be changed after cancellation';
  end if;

  old_rank := case old.status
    when 'draft' then 1
    when 'scheduled' then 2
    when 'live' then 3
    when 'completed' then 4
    when 'cancelled' then 5
    else null
  end;

  new_rank := case new.status
    when 'draft' then 1
    when 'scheduled' then 2
    when 'live' then 3
    when 'completed' then 4
    when 'cancelled' then 5
    else null
  end;

  if old_rank is null or new_rank is null then
    raise exception 'Invalid event status transition';
  end if;


  if new.status = 'cancelled' then
    return new;
  end if;

  if old.status = 'completed' then
    raise exception 'Event status cannot be changed after completion';
  end if;

  if new_rank < old_rank then
    raise exception 'Event status cannot move backwards (% -> %)', old.status, new.status;
  end if;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.grade_quiz_and_issue_certificate(p_quiz_id uuid, p_user_id uuid, p_answers jsonb)
 RETURNS TABLE(passed boolean, score text, correct_count integer, question_count integer, pass_score integer, certificate_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public'
AS $function$
declare
  v_user_id uuid;
  v_course_id uuid;
  v_course_title text;
  v_pass_score integer;
  v_correct_count integer := 0;
  v_question_count integer := 0;
  v_score_percent integer := 0;
  v_certificate_id uuid;
  v_answer jsonb;
  v_expected_text text;
  v_expected_int integer;
  v_expected_bool boolean;
  v_expected_arr integer[];
  v_given_int integer;
  v_given_bool boolean;
  v_given_arr integer[];
  caller_role text := auth.role();
  caller_uid uuid := auth.uid();
  q record;
begin
  -- Resolve caller -> user id mapping.
  if caller_role is null then
    v_user_id := p_user_id;
  elsif caller_role = 'service_role' then
    v_user_id := coalesce(p_user_id, caller_uid);
  else
    if caller_uid is null then
      raise insufficient_privilege using message = 'authenticated user required';
    end if;
    if p_user_id is not null and p_user_id <> caller_uid then
      raise insufficient_privilege using message = 'cannot grade for other users';
    end if;
    v_user_id := caller_uid;
  end if;

  if v_user_id is null then
    raise exception 'user_id is required';
  end if;

  select cq.course_id, cq.pass_score, c.title
    into v_course_id, v_pass_score, v_course_title
  from app.course_quizzes cq
  join app.courses c on c.id = cq.course_id
  where cq.id = p_quiz_id;

  if v_course_id is null then
    return query select false, '0%', 0, 0, 0, null::uuid;
    return;
  end if;

  if v_pass_score is null then
    v_pass_score := 0;
  end if;

  for q in
    select id, kind, correct
    from app.quiz_questions
    where quiz_id = p_quiz_id
    order by position
  loop
    v_question_count := v_question_count + 1;
    v_answer := p_answers -> q.id::text;
    v_expected_text := q.correct;

    if q.kind = 'single' then
      v_expected_int := null;
      if v_expected_text is not null and v_expected_text <> '' then
        begin
          v_expected_int := v_expected_text::int;
        exception when others then
          v_expected_int := null;
        end;
      end if;

      v_given_int := null;
      if v_answer is not null then
        begin
          v_given_int := (v_answer #>> '{}')::int;
        exception when others then
          v_given_int := null;
        end;
      end if;

      if v_expected_int is not null and v_given_int is not null and v_expected_int = v_given_int then
        v_correct_count := v_correct_count + 1;
      end if;
    elsif q.kind = 'multi' then
      v_expected_arr := null;
      if v_expected_text is not null and v_expected_text <> '' then
        v_expected_arr := string_to_array(
          regexp_replace(v_expected_text, '[^0-9,]', '', 'g'),
          ','
        )::int[];
      end if;

      v_given_arr := null;
      if v_answer is not null and jsonb_typeof(v_answer) = 'array' then
        select array_agg(distinct value::int order by value::int)
          into v_given_arr
        from jsonb_array_elements_text(v_answer) as value
        where value ~ '^-?\\d+$';
      end if;

      if v_expected_arr is not null then
        select array_agg(distinct value order by value)
          into v_expected_arr
        from unnest(v_expected_arr) as value;
      end if;

      if v_expected_arr is not null and v_given_arr is not null then
        if array_length(v_expected_arr, 1) = array_length(v_given_arr, 1)
           and v_expected_arr <@ v_given_arr
           and v_given_arr <@ v_expected_arr then
          v_correct_count := v_correct_count + 1;
        end if;
      end if;
    else
      v_expected_bool := null;
      if v_expected_text is not null then
        v_expected_bool := lower(v_expected_text) in ('true', 't', '1', 'yes');
      end if;

      v_given_bool := null;
      if v_answer is not null then
        begin
          v_given_bool := (v_answer #>> '{}')::boolean;
        exception when others then
          v_given_bool := null;
        end;
      end if;

      if v_expected_bool is not null and v_given_bool is not null and v_expected_bool = v_given_bool then
        v_correct_count := v_correct_count + 1;
      end if;
    end if;
  end loop;

  if v_question_count > 0 then
    v_score_percent := round(v_correct_count::numeric * 100 / v_question_count)::int;
  else
    v_score_percent := 0;
  end if;

  passed := v_score_percent >= v_pass_score;

  if passed then
    select id
      into v_certificate_id
      from app.certificates
     where user_id = v_user_id
       and course_id = v_course_id
     limit 1;

    if v_certificate_id is null then
      insert into app.certificates (
        user_id,
        course_id,
        title,
        status,
        issued_at,
        metadata,
        created_at,
        updated_at
      )
      values (
        v_user_id,
        v_course_id,
        coalesce(v_course_title, 'Course certificate'),
        'verified',
        now(),
        jsonb_build_object(
          'score_percent', v_score_percent,
          'correct_count', v_correct_count,
          'question_count', v_question_count,
          'pass_score', v_pass_score
        ),
        now(),
        now()
      )
      returning id into v_certificate_id;
    else
      update app.certificates
         set status = 'verified',
             issued_at = coalesce(issued_at, now()),
             metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
               'score_percent', v_score_percent,
               'correct_count', v_correct_count,
               'question_count', v_question_count,
               'pass_score', v_pass_score
             ),
             updated_at = now()
       where id = v_certificate_id;
    end if;
  end if;

  return query
    select passed,
           (v_score_percent::text || '%') as score,
           v_correct_count,
           v_question_count,
           v_pass_score,
           v_certificate_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.has_course_classroom_access(p_course_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
AS $function$
  select
    coalesce(app.is_admin(p_user_id), false)
    or exists (
      select 1 from app.courses c
      where c.id = p_course_id and c.created_by = p_user_id
    )
    or exists (
      select 1 from app.entitlements e
      where e.course_id = p_course_id and e.user_id = p_user_id
    )
    or exists (
      select 1 from app.enrollments en
      where en.course_id = p_course_id and en.user_id = p_user_id
    )
    or exists (
      select 1
      from app.memberships m
      where m.user_id = p_user_id
        and lower(coalesce(m.status, 'active')) not in (
          'canceled', 'unpaid', 'incomplete_expired', 'past_due'
        )
    );
$function$
;

CREATE OR REPLACE FUNCTION app.is_admin(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
AS $function$
  select exists (
    select 1 from app.profiles
    where user_id = p_user and is_admin = true
  );
$function$
;

CREATE OR REPLACE FUNCTION app.is_seminar_attendee(p_seminar_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select app.is_seminar_attendee(p_seminar_id, auth.uid());
$function$
;

CREATE OR REPLACE FUNCTION app.is_seminar_attendee(p_seminar_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
AS $function$
  select exists(
    select 1
    from app.seminar_attendees sa
    where sa.seminar_id = p_seminar_id
      and sa.user_id = p_user_id
  );
$function$
;

CREATE OR REPLACE FUNCTION app.is_seminar_host(p_seminar_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select app.is_seminar_host(p_seminar_id, auth.uid());
$function$
;

CREATE OR REPLACE FUNCTION app.is_seminar_host(p_seminar_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
begin
  if auth.role() <> 'service_role' and auth.uid() is distinct from p_user_id then
    raise insufficient_privilege using message = 'cannot check host status for other users';
  end if;

  return exists(
    select 1 from app.seminars s
    where s.id = p_seminar_id
      and s.host_id = p_user_id
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION app.is_teacher(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
AS $function$
  select
    app.is_admin(p_user)
    or exists (
      select 1
      from app.profiles p
      where p.user_id = p_user
        and coalesce(p.role_v2, 'user')::text in ('teacher', 'admin')
    )
    or exists (
      select 1
      from app.teacher_permissions tp
      where tp.profile_id = p_user
        and (tp.can_edit_courses = true or tp.can_publish = true)
    )
    or exists (
      select 1
      from app.teacher_approvals ta
      where ta.user_id = p_user
        and ta.approved_at is not null
    );
$function$
;

CREATE OR REPLACE FUNCTION app.normalize_runtime_media_kind(raw_kind text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case lower(coalesce(trim(raw_kind), 'other'))
    when 'audio' then 'audio'
    when 'video' then 'video'
    when 'image' then 'image'
    when 'pdf' then 'document'
    when 'document' then 'document'
    else 'other'
  end
$function$
;

CREATE OR REPLACE FUNCTION app.runtime_media_lesson_fallback_policy(lesson_kind text, media_asset_id uuid, media_object_id uuid, legacy_storage_path text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when media_asset_id is null then 'legacy_only'
    when lower(coalesce(trim(lesson_kind), '')) = 'audio' then 'never'
    when media_object_id is not null then 'if_no_ready_asset'
    when nullif(trim(legacy_storage_path), '') is not null then 'if_no_ready_asset'
    else 'never'
  end
$function$
;

create or replace view "app"."service_orders" as  SELECT o.id,
    o.user_id,
    buyer.display_name AS buyer_display_name,
    buyer.email AS buyer_email,
    o.service_id,
    s.title AS service_title,
    s.description AS service_description,
    s.duration_min AS service_duration_min,
    s.requires_certification AS service_requires_certification,
    s.certified_area AS service_certified_area,
    s.provider_id,
    provider.display_name AS provider_display_name,
    provider.email AS provider_email,
    o.amount_cents,
    o.currency,
    o.status,
    o.stripe_checkout_id,
    o.stripe_payment_intent,
    o.metadata,
    o.created_at,
    o.updated_at
   FROM (((app.orders o
     JOIN app.services s ON ((s.id = o.service_id)))
     LEFT JOIN app.profiles buyer ON ((buyer.user_id = o.user_id)))
     LEFT JOIN app.profiles provider ON ((provider.user_id = s.provider_id)))
  WHERE (o.service_id IS NOT NULL);


create or replace view "app"."service_reviews" as  SELECT id,
    service_id,
    order_id,
    reviewer_id,
    rating,
    comment,
    visibility,
    created_at
   FROM app.reviews r
  WHERE (service_id IS NOT NULL);


CREATE OR REPLACE FUNCTION app.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.sync_runtime_media_course_context_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  perform app.upsert_runtime_media_for_lesson_media(lm.id)
  from app.lesson_media lm
  join app.lessons l on l.id = lm.lesson_id
  where l.course_id = new.id;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.sync_runtime_media_lesson_context_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  perform app.upsert_runtime_media_for_lesson_media(lm.id)
  from app.lesson_media lm
  where lm.lesson_id = new.id;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.sync_runtime_media_lesson_media_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  perform app.upsert_runtime_media_for_lesson_media(new.id);
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.touch_course_display_priorities()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.touch_course_entitlements()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end; $function$
;

CREATE OR REPLACE FUNCTION app.touch_events()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.touch_home_player_course_links()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.touch_home_player_uploads()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.touch_intro_usage()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.touch_livekit_webhook_jobs()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
    begin
      new.updated_at = now();
      return new;
    end;
    $function$
;

CREATE OR REPLACE FUNCTION app.touch_teacher_profile_media()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.upsert_runtime_media_for_lesson_media(target_lesson_media_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
declare
  runtime_id uuid;
begin
  insert into app.runtime_media (
    reference_type,
    auth_scope,
    fallback_policy,
    lesson_media_id,
    teacher_id,
    course_id,
    lesson_id,
    media_asset_id,
    media_object_id,
    legacy_storage_bucket,
    legacy_storage_path,
    kind,
    active,
    created_at,
    updated_at
  )
  select
    'lesson_media',
    'lesson_course',
    app.runtime_media_lesson_fallback_policy(
      lm.kind,
      lm.media_asset_id,
      lm.media_id,
      lm.storage_path
    ),
    lm.id,
    coalesce(c.created_by, ma.owner_id, mo.owner_id),
    l.course_id,
    lm.lesson_id,
    lm.media_asset_id,
    lm.media_id,
    case
      when nullif(trim(lm.storage_path), '') is not null
        then coalesce(nullif(trim(lm.storage_bucket), ''), 'lesson-media')
      else null
    end,
    nullif(trim(lm.storage_path), ''),
    app.normalize_runtime_media_kind(lm.kind),
    true,
    coalesce(lm.created_at, now()),
    now()
  from app.lesson_media lm
  join app.lessons l on l.id = lm.lesson_id
  join app.courses c on c.id = l.course_id
  left join app.media_objects mo on mo.id = lm.media_id
  left join app.media_assets ma on ma.id = lm.media_asset_id
  where lm.id = target_lesson_media_id
  on conflict (lesson_media_id) do update
    set reference_type = excluded.reference_type,
        auth_scope = excluded.auth_scope,
        fallback_policy = excluded.fallback_policy,
        teacher_id = excluded.teacher_id,
        course_id = excluded.course_id,
        lesson_id = excluded.lesson_id,
        media_asset_id = excluded.media_asset_id,
        media_object_id = excluded.media_object_id,
        legacy_storage_bucket = excluded.legacy_storage_bucket,
        legacy_storage_path = excluded.legacy_storage_path,
        kind = excluded.kind,
        active = excluded.active,
        updated_at = now()
  returning id into runtime_id;

  return runtime_id;
end;
$function$
;

create or replace view "app"."v_meditation_audio_library" as  SELECT lm.id AS media_id,
    l.course_id,
    l.id AS lesson_id,
    l.title,
    NULL::text AS description,
    COALESCE(mo.storage_path, lm.storage_path) AS storage_path,
    COALESCE(mo.storage_bucket, lm.storage_bucket, 'lesson-media'::text) AS storage_bucket,
    lm.duration_seconds,
    lm.created_at
   FROM ((app.lesson_media lm
     JOIN app.lessons l ON ((l.id = lm.lesson_id)))
     LEFT JOIN app.media_objects mo ON ((mo.id = lm.media_id)))
  WHERE (lower(lm.kind) = 'audio'::text);


CREATE OR REPLACE FUNCTION public.rest_insert_seminar(p_host_id uuid, p_title text, p_status app.seminar_status)
 RETURNS app.seminars
 LANGUAGE plpgsql
AS $function$
declare
  created_row app.seminars%rowtype;
begin
  insert into app.seminars (host_id, title, status)
  values (p_host_id, p_title, p_status)
  returning * into created_row;

  return created_row;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.rest_select_seminar(p_seminar_id uuid)
 RETURNS SETOF app.seminars
 LANGUAGE sql
 STABLE
AS $function$
  select *
  from app.seminars
  where id = p_seminar_id;
$function$
;

CREATE OR REPLACE FUNCTION public.rest_select_seminar_attendees(p_seminar_id uuid)
 RETURNS SETOF app.seminar_attendees
 LANGUAGE sql
 STABLE
AS $function$
  select *
  from app.seminar_attendees
  where seminar_id = p_seminar_id;
$function$
;

CREATE OR REPLACE FUNCTION public.rest_update_seminar_description(p_seminar_id uuid, p_description text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  updated_row app.seminars%rowtype;
begin
  update app.seminars
  set description = p_description
  where id = p_seminar_id
  returning * into updated_row;

  if not found then
    return jsonb_build_object('id', null, 'description', null);
  end if;

  return to_jsonb(updated_row);
end;
$function$
;

grant delete on table "app"."activities" to "anon";

grant insert on table "app"."activities" to "anon";

grant select on table "app"."activities" to "anon";

grant update on table "app"."activities" to "anon";

grant delete on table "app"."activities" to "authenticated";

grant insert on table "app"."activities" to "authenticated";

grant select on table "app"."activities" to "authenticated";

grant update on table "app"."activities" to "authenticated";

grant delete on table "app"."activities" to "service_role";

grant insert on table "app"."activities" to "service_role";

grant select on table "app"."activities" to "service_role";

grant update on table "app"."activities" to "service_role";

grant delete on table "app"."app_config" to "anon";

grant insert on table "app"."app_config" to "anon";

grant select on table "app"."app_config" to "anon";

grant update on table "app"."app_config" to "anon";

grant delete on table "app"."app_config" to "authenticated";

grant insert on table "app"."app_config" to "authenticated";

grant select on table "app"."app_config" to "authenticated";

grant update on table "app"."app_config" to "authenticated";

grant delete on table "app"."app_config" to "service_role";

grant insert on table "app"."app_config" to "service_role";

grant select on table "app"."app_config" to "service_role";

grant update on table "app"."app_config" to "service_role";

grant delete on table "app"."auth_events" to "anon";

grant insert on table "app"."auth_events" to "anon";

grant select on table "app"."auth_events" to "anon";

grant update on table "app"."auth_events" to "anon";

grant delete on table "app"."auth_events" to "authenticated";

grant insert on table "app"."auth_events" to "authenticated";

grant select on table "app"."auth_events" to "authenticated";

grant update on table "app"."auth_events" to "authenticated";

grant delete on table "app"."auth_events" to "service_role";

grant insert on table "app"."auth_events" to "service_role";

grant select on table "app"."auth_events" to "service_role";

grant update on table "app"."auth_events" to "service_role";

grant delete on table "app"."billing_logs" to "anon";

grant insert on table "app"."billing_logs" to "anon";

grant select on table "app"."billing_logs" to "anon";

grant update on table "app"."billing_logs" to "anon";

grant delete on table "app"."billing_logs" to "authenticated";

grant insert on table "app"."billing_logs" to "authenticated";

grant select on table "app"."billing_logs" to "authenticated";

grant update on table "app"."billing_logs" to "authenticated";

grant delete on table "app"."billing_logs" to "service_role";

grant insert on table "app"."billing_logs" to "service_role";

grant select on table "app"."billing_logs" to "service_role";

grant update on table "app"."billing_logs" to "service_role";

grant delete on table "app"."certificates" to "anon";

grant insert on table "app"."certificates" to "anon";

grant select on table "app"."certificates" to "anon";

grant update on table "app"."certificates" to "anon";

grant delete on table "app"."certificates" to "authenticated";

grant insert on table "app"."certificates" to "authenticated";

grant select on table "app"."certificates" to "authenticated";

grant update on table "app"."certificates" to "authenticated";

grant delete on table "app"."certificates" to "service_role";

grant insert on table "app"."certificates" to "service_role";

grant select on table "app"."certificates" to "service_role";

grant update on table "app"."certificates" to "service_role";

grant delete on table "app"."classroom_messages" to "anon";

grant insert on table "app"."classroom_messages" to "anon";

grant select on table "app"."classroom_messages" to "anon";

grant update on table "app"."classroom_messages" to "anon";

grant delete on table "app"."classroom_messages" to "authenticated";

grant insert on table "app"."classroom_messages" to "authenticated";

grant select on table "app"."classroom_messages" to "authenticated";

grant update on table "app"."classroom_messages" to "authenticated";

grant delete on table "app"."classroom_messages" to "service_role";

grant insert on table "app"."classroom_messages" to "service_role";

grant select on table "app"."classroom_messages" to "service_role";

grant update on table "app"."classroom_messages" to "service_role";

grant delete on table "app"."classroom_presence" to "anon";

grant insert on table "app"."classroom_presence" to "anon";

grant select on table "app"."classroom_presence" to "anon";

grant update on table "app"."classroom_presence" to "anon";

grant delete on table "app"."classroom_presence" to "authenticated";

grant insert on table "app"."classroom_presence" to "authenticated";

grant select on table "app"."classroom_presence" to "authenticated";

grant update on table "app"."classroom_presence" to "authenticated";

grant delete on table "app"."classroom_presence" to "service_role";

grant insert on table "app"."classroom_presence" to "service_role";

grant select on table "app"."classroom_presence" to "service_role";

grant update on table "app"."classroom_presence" to "service_role";

grant delete on table "app"."course_bundle_courses" to "anon";

grant insert on table "app"."course_bundle_courses" to "anon";

grant select on table "app"."course_bundle_courses" to "anon";

grant update on table "app"."course_bundle_courses" to "anon";

grant delete on table "app"."course_bundle_courses" to "authenticated";

grant insert on table "app"."course_bundle_courses" to "authenticated";

grant select on table "app"."course_bundle_courses" to "authenticated";

grant update on table "app"."course_bundle_courses" to "authenticated";

grant delete on table "app"."course_bundle_courses" to "service_role";

grant insert on table "app"."course_bundle_courses" to "service_role";

grant select on table "app"."course_bundle_courses" to "service_role";

grant update on table "app"."course_bundle_courses" to "service_role";

grant delete on table "app"."course_bundles" to "anon";

grant insert on table "app"."course_bundles" to "anon";

grant select on table "app"."course_bundles" to "anon";

grant update on table "app"."course_bundles" to "anon";

grant delete on table "app"."course_bundles" to "authenticated";

grant insert on table "app"."course_bundles" to "authenticated";

grant select on table "app"."course_bundles" to "authenticated";

grant update on table "app"."course_bundles" to "authenticated";

grant delete on table "app"."course_bundles" to "service_role";

grant insert on table "app"."course_bundles" to "service_role";

grant select on table "app"."course_bundles" to "service_role";

grant update on table "app"."course_bundles" to "service_role";

grant delete on table "app"."course_display_priorities" to "anon";

grant insert on table "app"."course_display_priorities" to "anon";

grant select on table "app"."course_display_priorities" to "anon";

grant update on table "app"."course_display_priorities" to "anon";

grant delete on table "app"."course_display_priorities" to "authenticated";

grant insert on table "app"."course_display_priorities" to "authenticated";

grant select on table "app"."course_display_priorities" to "authenticated";

grant update on table "app"."course_display_priorities" to "authenticated";

grant delete on table "app"."course_display_priorities" to "service_role";

grant insert on table "app"."course_display_priorities" to "service_role";

grant select on table "app"."course_display_priorities" to "service_role";

grant update on table "app"."course_display_priorities" to "service_role";

grant delete on table "app"."course_entitlements" to "anon";

grant insert on table "app"."course_entitlements" to "anon";

grant select on table "app"."course_entitlements" to "anon";

grant update on table "app"."course_entitlements" to "anon";

grant delete on table "app"."course_entitlements" to "authenticated";

grant insert on table "app"."course_entitlements" to "authenticated";

grant select on table "app"."course_entitlements" to "authenticated";

grant update on table "app"."course_entitlements" to "authenticated";

grant delete on table "app"."course_entitlements" to "service_role";

grant insert on table "app"."course_entitlements" to "service_role";

grant select on table "app"."course_entitlements" to "service_role";

grant update on table "app"."course_entitlements" to "service_role";

grant delete on table "app"."course_products" to "anon";

grant insert on table "app"."course_products" to "anon";

grant select on table "app"."course_products" to "anon";

grant update on table "app"."course_products" to "anon";

grant delete on table "app"."course_products" to "authenticated";

grant insert on table "app"."course_products" to "authenticated";

grant select on table "app"."course_products" to "authenticated";

grant update on table "app"."course_products" to "authenticated";

grant delete on table "app"."course_products" to "service_role";

grant insert on table "app"."course_products" to "service_role";

grant select on table "app"."course_products" to "service_role";

grant update on table "app"."course_products" to "service_role";

grant delete on table "app"."course_quizzes" to "anon";

grant insert on table "app"."course_quizzes" to "anon";

grant select on table "app"."course_quizzes" to "anon";

grant update on table "app"."course_quizzes" to "anon";

grant delete on table "app"."course_quizzes" to "authenticated";

grant insert on table "app"."course_quizzes" to "authenticated";

grant select on table "app"."course_quizzes" to "authenticated";

grant update on table "app"."course_quizzes" to "authenticated";

grant delete on table "app"."course_quizzes" to "service_role";

grant insert on table "app"."course_quizzes" to "service_role";

grant select on table "app"."course_quizzes" to "service_role";

grant update on table "app"."course_quizzes" to "service_role";

grant delete on table "app"."courses" to "anon";

grant insert on table "app"."courses" to "anon";

grant select on table "app"."courses" to "anon";

grant update on table "app"."courses" to "anon";

grant delete on table "app"."courses" to "authenticated";

grant insert on table "app"."courses" to "authenticated";

grant select on table "app"."courses" to "authenticated";

grant update on table "app"."courses" to "authenticated";

grant delete on table "app"."courses" to "service_role";

grant insert on table "app"."courses" to "service_role";

grant select on table "app"."courses" to "service_role";

grant update on table "app"."courses" to "service_role";

grant delete on table "app"."enrollments" to "anon";

grant insert on table "app"."enrollments" to "anon";

grant select on table "app"."enrollments" to "anon";

grant update on table "app"."enrollments" to "anon";

grant delete on table "app"."enrollments" to "authenticated";

grant insert on table "app"."enrollments" to "authenticated";

grant select on table "app"."enrollments" to "authenticated";

grant update on table "app"."enrollments" to "authenticated";

grant delete on table "app"."enrollments" to "service_role";

grant insert on table "app"."enrollments" to "service_role";

grant select on table "app"."enrollments" to "service_role";

grant update on table "app"."enrollments" to "service_role";

grant delete on table "app"."entitlements" to "anon";

grant insert on table "app"."entitlements" to "anon";

grant select on table "app"."entitlements" to "anon";

grant update on table "app"."entitlements" to "anon";

grant delete on table "app"."entitlements" to "authenticated";

grant insert on table "app"."entitlements" to "authenticated";

grant select on table "app"."entitlements" to "authenticated";

grant update on table "app"."entitlements" to "authenticated";

grant delete on table "app"."entitlements" to "service_role";

grant insert on table "app"."entitlements" to "service_role";

grant select on table "app"."entitlements" to "service_role";

grant update on table "app"."entitlements" to "service_role";

grant delete on table "app"."event_participants" to "anon";

grant insert on table "app"."event_participants" to "anon";

grant select on table "app"."event_participants" to "anon";

grant update on table "app"."event_participants" to "anon";

grant delete on table "app"."event_participants" to "authenticated";

grant insert on table "app"."event_participants" to "authenticated";

grant select on table "app"."event_participants" to "authenticated";

grant update on table "app"."event_participants" to "authenticated";

grant delete on table "app"."event_participants" to "service_role";

grant insert on table "app"."event_participants" to "service_role";

grant select on table "app"."event_participants" to "service_role";

grant update on table "app"."event_participants" to "service_role";

grant delete on table "app"."events" to "anon";

grant insert on table "app"."events" to "anon";

grant select on table "app"."events" to "anon";

grant update on table "app"."events" to "anon";

grant delete on table "app"."events" to "authenticated";

grant insert on table "app"."events" to "authenticated";

grant select on table "app"."events" to "authenticated";

grant update on table "app"."events" to "authenticated";

grant delete on table "app"."events" to "service_role";

grant insert on table "app"."events" to "service_role";

grant select on table "app"."events" to "service_role";

grant update on table "app"."events" to "service_role";

grant delete on table "app"."follows" to "anon";

grant insert on table "app"."follows" to "anon";

grant select on table "app"."follows" to "anon";

grant update on table "app"."follows" to "anon";

grant delete on table "app"."follows" to "authenticated";

grant insert on table "app"."follows" to "authenticated";

grant select on table "app"."follows" to "authenticated";

grant update on table "app"."follows" to "authenticated";

grant delete on table "app"."follows" to "service_role";

grant insert on table "app"."follows" to "service_role";

grant select on table "app"."follows" to "service_role";

grant update on table "app"."follows" to "service_role";

grant delete on table "app"."guest_claim_tokens" to "anon";

grant insert on table "app"."guest_claim_tokens" to "anon";

grant select on table "app"."guest_claim_tokens" to "anon";

grant update on table "app"."guest_claim_tokens" to "anon";

grant delete on table "app"."guest_claim_tokens" to "authenticated";

grant insert on table "app"."guest_claim_tokens" to "authenticated";

grant select on table "app"."guest_claim_tokens" to "authenticated";

grant update on table "app"."guest_claim_tokens" to "authenticated";

grant delete on table "app"."guest_claim_tokens" to "service_role";

grant insert on table "app"."guest_claim_tokens" to "service_role";

grant select on table "app"."guest_claim_tokens" to "service_role";

grant update on table "app"."guest_claim_tokens" to "service_role";

grant delete on table "app"."home_player_course_links" to "anon";

grant insert on table "app"."home_player_course_links" to "anon";

grant select on table "app"."home_player_course_links" to "anon";

grant update on table "app"."home_player_course_links" to "anon";

grant delete on table "app"."home_player_course_links" to "authenticated";

grant insert on table "app"."home_player_course_links" to "authenticated";

grant select on table "app"."home_player_course_links" to "authenticated";

grant update on table "app"."home_player_course_links" to "authenticated";

grant delete on table "app"."home_player_course_links" to "service_role";

grant insert on table "app"."home_player_course_links" to "service_role";

grant select on table "app"."home_player_course_links" to "service_role";

grant update on table "app"."home_player_course_links" to "service_role";

grant delete on table "app"."home_player_uploads" to "anon";

grant insert on table "app"."home_player_uploads" to "anon";

grant select on table "app"."home_player_uploads" to "anon";

grant update on table "app"."home_player_uploads" to "anon";

grant delete on table "app"."home_player_uploads" to "authenticated";

grant insert on table "app"."home_player_uploads" to "authenticated";

grant select on table "app"."home_player_uploads" to "authenticated";

grant update on table "app"."home_player_uploads" to "authenticated";

grant delete on table "app"."home_player_uploads" to "service_role";

grant insert on table "app"."home_player_uploads" to "service_role";

grant select on table "app"."home_player_uploads" to "service_role";

grant update on table "app"."home_player_uploads" to "service_role";

grant delete on table "app"."intro_usage" to "anon";

grant insert on table "app"."intro_usage" to "anon";

grant select on table "app"."intro_usage" to "anon";

grant update on table "app"."intro_usage" to "anon";

grant delete on table "app"."intro_usage" to "authenticated";

grant insert on table "app"."intro_usage" to "authenticated";

grant select on table "app"."intro_usage" to "authenticated";

grant update on table "app"."intro_usage" to "authenticated";

grant delete on table "app"."intro_usage" to "service_role";

grant insert on table "app"."intro_usage" to "service_role";

grant select on table "app"."intro_usage" to "service_role";

grant update on table "app"."intro_usage" to "service_role";

grant delete on table "app"."lesson_media" to "anon";

grant insert on table "app"."lesson_media" to "anon";

grant select on table "app"."lesson_media" to "anon";

grant update on table "app"."lesson_media" to "anon";

grant delete on table "app"."lesson_media" to "authenticated";

grant insert on table "app"."lesson_media" to "authenticated";

grant select on table "app"."lesson_media" to "authenticated";

grant update on table "app"."lesson_media" to "authenticated";

grant delete on table "app"."lesson_media" to "service_role";

grant insert on table "app"."lesson_media" to "service_role";

grant select on table "app"."lesson_media" to "service_role";

grant update on table "app"."lesson_media" to "service_role";

grant delete on table "app"."lesson_media_issues" to "anon";

grant insert on table "app"."lesson_media_issues" to "anon";

grant select on table "app"."lesson_media_issues" to "anon";

grant update on table "app"."lesson_media_issues" to "anon";

grant delete on table "app"."lesson_media_issues" to "authenticated";

grant insert on table "app"."lesson_media_issues" to "authenticated";

grant select on table "app"."lesson_media_issues" to "authenticated";

grant update on table "app"."lesson_media_issues" to "authenticated";

grant delete on table "app"."lesson_media_issues" to "service_role";

grant insert on table "app"."lesson_media_issues" to "service_role";

grant select on table "app"."lesson_media_issues" to "service_role";

grant update on table "app"."lesson_media_issues" to "service_role";

grant delete on table "app"."lesson_packages" to "anon";

grant insert on table "app"."lesson_packages" to "anon";

grant select on table "app"."lesson_packages" to "anon";

grant update on table "app"."lesson_packages" to "anon";

grant delete on table "app"."lesson_packages" to "authenticated";

grant insert on table "app"."lesson_packages" to "authenticated";

grant select on table "app"."lesson_packages" to "authenticated";

grant update on table "app"."lesson_packages" to "authenticated";

grant delete on table "app"."lesson_packages" to "service_role";

grant insert on table "app"."lesson_packages" to "service_role";

grant select on table "app"."lesson_packages" to "service_role";

grant update on table "app"."lesson_packages" to "service_role";

grant delete on table "app"."lessons" to "anon";

grant insert on table "app"."lessons" to "anon";

grant select on table "app"."lessons" to "anon";

grant update on table "app"."lessons" to "anon";

grant delete on table "app"."lessons" to "authenticated";

grant insert on table "app"."lessons" to "authenticated";

grant select on table "app"."lessons" to "authenticated";

grant update on table "app"."lessons" to "authenticated";

grant delete on table "app"."lessons" to "service_role";

grant insert on table "app"."lessons" to "service_role";

grant select on table "app"."lessons" to "service_role";

grant update on table "app"."lessons" to "service_role";

grant delete on table "app"."live_event_registrations" to "anon";

grant insert on table "app"."live_event_registrations" to "anon";

grant select on table "app"."live_event_registrations" to "anon";

grant update on table "app"."live_event_registrations" to "anon";

grant delete on table "app"."live_event_registrations" to "authenticated";

grant insert on table "app"."live_event_registrations" to "authenticated";

grant select on table "app"."live_event_registrations" to "authenticated";

grant update on table "app"."live_event_registrations" to "authenticated";

grant delete on table "app"."live_event_registrations" to "service_role";

grant insert on table "app"."live_event_registrations" to "service_role";

grant select on table "app"."live_event_registrations" to "service_role";

grant update on table "app"."live_event_registrations" to "service_role";

grant delete on table "app"."live_events" to "anon";

grant insert on table "app"."live_events" to "anon";

grant select on table "app"."live_events" to "anon";

grant update on table "app"."live_events" to "anon";

grant delete on table "app"."live_events" to "authenticated";

grant insert on table "app"."live_events" to "authenticated";

grant select on table "app"."live_events" to "authenticated";

grant update on table "app"."live_events" to "authenticated";

grant delete on table "app"."live_events" to "service_role";

grant insert on table "app"."live_events" to "service_role";

grant select on table "app"."live_events" to "service_role";

grant update on table "app"."live_events" to "service_role";

grant delete on table "app"."livekit_webhook_jobs" to "anon";

grant insert on table "app"."livekit_webhook_jobs" to "anon";

grant select on table "app"."livekit_webhook_jobs" to "anon";

grant update on table "app"."livekit_webhook_jobs" to "anon";

grant delete on table "app"."livekit_webhook_jobs" to "authenticated";

grant insert on table "app"."livekit_webhook_jobs" to "authenticated";

grant select on table "app"."livekit_webhook_jobs" to "authenticated";

grant update on table "app"."livekit_webhook_jobs" to "authenticated";

grant delete on table "app"."livekit_webhook_jobs" to "service_role";

grant insert on table "app"."livekit_webhook_jobs" to "service_role";

grant select on table "app"."livekit_webhook_jobs" to "service_role";

grant update on table "app"."livekit_webhook_jobs" to "service_role";

grant delete on table "app"."media_assets" to "anon";

grant insert on table "app"."media_assets" to "anon";

grant select on table "app"."media_assets" to "anon";

grant update on table "app"."media_assets" to "anon";

grant delete on table "app"."media_assets" to "authenticated";

grant insert on table "app"."media_assets" to "authenticated";

grant select on table "app"."media_assets" to "authenticated";

grant update on table "app"."media_assets" to "authenticated";

grant delete on table "app"."media_assets" to "service_role";

grant insert on table "app"."media_assets" to "service_role";

grant select on table "app"."media_assets" to "service_role";

grant update on table "app"."media_assets" to "service_role";

grant delete on table "app"."media_objects" to "anon";

grant insert on table "app"."media_objects" to "anon";

grant select on table "app"."media_objects" to "anon";

grant update on table "app"."media_objects" to "anon";

grant delete on table "app"."media_objects" to "authenticated";

grant insert on table "app"."media_objects" to "authenticated";

grant select on table "app"."media_objects" to "authenticated";

grant update on table "app"."media_objects" to "authenticated";

grant delete on table "app"."media_objects" to "service_role";

grant insert on table "app"."media_objects" to "service_role";

grant select on table "app"."media_objects" to "service_role";

grant update on table "app"."media_objects" to "service_role";

grant delete on table "app"."media_resolution_failures" to "anon";

grant insert on table "app"."media_resolution_failures" to "anon";

grant select on table "app"."media_resolution_failures" to "anon";

grant update on table "app"."media_resolution_failures" to "anon";

grant delete on table "app"."media_resolution_failures" to "authenticated";

grant insert on table "app"."media_resolution_failures" to "authenticated";

grant select on table "app"."media_resolution_failures" to "authenticated";

grant update on table "app"."media_resolution_failures" to "authenticated";

grant delete on table "app"."media_resolution_failures" to "service_role";

grant insert on table "app"."media_resolution_failures" to "service_role";

grant select on table "app"."media_resolution_failures" to "service_role";

grant update on table "app"."media_resolution_failures" to "service_role";

grant delete on table "app"."meditations" to "anon";

grant insert on table "app"."meditations" to "anon";

grant select on table "app"."meditations" to "anon";

grant update on table "app"."meditations" to "anon";

grant delete on table "app"."meditations" to "authenticated";

grant insert on table "app"."meditations" to "authenticated";

grant select on table "app"."meditations" to "authenticated";

grant update on table "app"."meditations" to "authenticated";

grant delete on table "app"."meditations" to "service_role";

grant insert on table "app"."meditations" to "service_role";

grant select on table "app"."meditations" to "service_role";

grant update on table "app"."meditations" to "service_role";

grant delete on table "app"."memberships" to "anon";

grant insert on table "app"."memberships" to "anon";

grant select on table "app"."memberships" to "anon";

grant update on table "app"."memberships" to "anon";

grant delete on table "app"."memberships" to "authenticated";

grant insert on table "app"."memberships" to "authenticated";

grant select on table "app"."memberships" to "authenticated";

grant update on table "app"."memberships" to "authenticated";

grant delete on table "app"."memberships" to "service_role";

grant insert on table "app"."memberships" to "service_role";

grant select on table "app"."memberships" to "service_role";

grant update on table "app"."memberships" to "service_role";

grant delete on table "app"."messages" to "anon";

grant insert on table "app"."messages" to "anon";

grant select on table "app"."messages" to "anon";

grant update on table "app"."messages" to "anon";

grant delete on table "app"."messages" to "authenticated";

grant insert on table "app"."messages" to "authenticated";

grant select on table "app"."messages" to "authenticated";

grant update on table "app"."messages" to "authenticated";

grant delete on table "app"."messages" to "service_role";

grant insert on table "app"."messages" to "service_role";

grant select on table "app"."messages" to "service_role";

grant update on table "app"."messages" to "service_role";

grant delete on table "app"."music_tracks" to "anon";

grant insert on table "app"."music_tracks" to "anon";

grant select on table "app"."music_tracks" to "anon";

grant update on table "app"."music_tracks" to "anon";

grant delete on table "app"."music_tracks" to "authenticated";

grant insert on table "app"."music_tracks" to "authenticated";

grant select on table "app"."music_tracks" to "authenticated";

grant update on table "app"."music_tracks" to "authenticated";

grant delete on table "app"."music_tracks" to "service_role";

grant insert on table "app"."music_tracks" to "service_role";

grant select on table "app"."music_tracks" to "service_role";

grant update on table "app"."music_tracks" to "service_role";

grant delete on table "app"."notification_audiences" to "anon";

grant insert on table "app"."notification_audiences" to "anon";

grant select on table "app"."notification_audiences" to "anon";

grant update on table "app"."notification_audiences" to "anon";

grant delete on table "app"."notification_audiences" to "authenticated";

grant insert on table "app"."notification_audiences" to "authenticated";

grant select on table "app"."notification_audiences" to "authenticated";

grant update on table "app"."notification_audiences" to "authenticated";

grant delete on table "app"."notification_audiences" to "service_role";

grant insert on table "app"."notification_audiences" to "service_role";

grant select on table "app"."notification_audiences" to "service_role";

grant update on table "app"."notification_audiences" to "service_role";

grant delete on table "app"."notification_campaigns" to "anon";

grant insert on table "app"."notification_campaigns" to "anon";

grant select on table "app"."notification_campaigns" to "anon";

grant update on table "app"."notification_campaigns" to "anon";

grant delete on table "app"."notification_campaigns" to "authenticated";

grant insert on table "app"."notification_campaigns" to "authenticated";

grant select on table "app"."notification_campaigns" to "authenticated";

grant update on table "app"."notification_campaigns" to "authenticated";

grant delete on table "app"."notification_campaigns" to "service_role";

grant insert on table "app"."notification_campaigns" to "service_role";

grant select on table "app"."notification_campaigns" to "service_role";

grant update on table "app"."notification_campaigns" to "service_role";

grant delete on table "app"."notification_deliveries" to "anon";

grant insert on table "app"."notification_deliveries" to "anon";

grant select on table "app"."notification_deliveries" to "anon";

grant update on table "app"."notification_deliveries" to "anon";

grant delete on table "app"."notification_deliveries" to "authenticated";

grant insert on table "app"."notification_deliveries" to "authenticated";

grant select on table "app"."notification_deliveries" to "authenticated";

grant update on table "app"."notification_deliveries" to "authenticated";

grant delete on table "app"."notification_deliveries" to "service_role";

grant insert on table "app"."notification_deliveries" to "service_role";

grant select on table "app"."notification_deliveries" to "service_role";

grant update on table "app"."notification_deliveries" to "service_role";

grant delete on table "app"."notifications" to "anon";

grant insert on table "app"."notifications" to "anon";

grant select on table "app"."notifications" to "anon";

grant update on table "app"."notifications" to "anon";

grant delete on table "app"."notifications" to "authenticated";

grant insert on table "app"."notifications" to "authenticated";

grant select on table "app"."notifications" to "authenticated";

grant update on table "app"."notifications" to "authenticated";

grant delete on table "app"."notifications" to "service_role";

grant insert on table "app"."notifications" to "service_role";

grant select on table "app"."notifications" to "service_role";

grant update on table "app"."notifications" to "service_role";

grant delete on table "app"."orders" to "anon";

grant insert on table "app"."orders" to "anon";

grant select on table "app"."orders" to "anon";

grant update on table "app"."orders" to "anon";

grant delete on table "app"."orders" to "authenticated";

grant insert on table "app"."orders" to "authenticated";

grant select on table "app"."orders" to "authenticated";

grant update on table "app"."orders" to "authenticated";

grant delete on table "app"."orders" to "service_role";

grant insert on table "app"."orders" to "service_role";

grant select on table "app"."orders" to "service_role";

grant update on table "app"."orders" to "service_role";

grant delete on table "app"."payment_events" to "anon";

grant insert on table "app"."payment_events" to "anon";

grant select on table "app"."payment_events" to "anon";

grant update on table "app"."payment_events" to "anon";

grant delete on table "app"."payment_events" to "authenticated";

grant insert on table "app"."payment_events" to "authenticated";

grant select on table "app"."payment_events" to "authenticated";

grant update on table "app"."payment_events" to "authenticated";

grant delete on table "app"."payment_events" to "service_role";

grant insert on table "app"."payment_events" to "service_role";

grant select on table "app"."payment_events" to "service_role";

grant update on table "app"."payment_events" to "service_role";

grant delete on table "app"."payments" to "anon";

grant insert on table "app"."payments" to "anon";

grant select on table "app"."payments" to "anon";

grant update on table "app"."payments" to "anon";

grant delete on table "app"."payments" to "authenticated";

grant insert on table "app"."payments" to "authenticated";

grant select on table "app"."payments" to "authenticated";

grant update on table "app"."payments" to "authenticated";

grant delete on table "app"."payments" to "service_role";

grant insert on table "app"."payments" to "service_role";

grant select on table "app"."payments" to "service_role";

grant update on table "app"."payments" to "service_role";

grant delete on table "app"."posts" to "anon";

grant insert on table "app"."posts" to "anon";

grant select on table "app"."posts" to "anon";

grant update on table "app"."posts" to "anon";

grant delete on table "app"."posts" to "authenticated";

grant insert on table "app"."posts" to "authenticated";

grant select on table "app"."posts" to "authenticated";

grant update on table "app"."posts" to "authenticated";

grant delete on table "app"."posts" to "service_role";

grant insert on table "app"."posts" to "service_role";

grant select on table "app"."posts" to "service_role";

grant update on table "app"."posts" to "service_role";

grant delete on table "app"."profiles" to "anon";

grant insert on table "app"."profiles" to "anon";

grant select on table "app"."profiles" to "anon";

grant update on table "app"."profiles" to "anon";

grant delete on table "app"."profiles" to "authenticated";

grant insert on table "app"."profiles" to "authenticated";

grant select on table "app"."profiles" to "authenticated";

grant update on table "app"."profiles" to "authenticated";

grant delete on table "app"."profiles" to "service_role";

grant insert on table "app"."profiles" to "service_role";

grant select on table "app"."profiles" to "service_role";

grant update on table "app"."profiles" to "service_role";

grant delete on table "app"."purchases" to "anon";

grant insert on table "app"."purchases" to "anon";

grant select on table "app"."purchases" to "anon";

grant update on table "app"."purchases" to "anon";

grant delete on table "app"."purchases" to "authenticated";

grant insert on table "app"."purchases" to "authenticated";

grant select on table "app"."purchases" to "authenticated";

grant update on table "app"."purchases" to "authenticated";

grant delete on table "app"."purchases" to "service_role";

grant insert on table "app"."purchases" to "service_role";

grant select on table "app"."purchases" to "service_role";

grant update on table "app"."purchases" to "service_role";

grant delete on table "app"."quiz_questions" to "anon";

grant insert on table "app"."quiz_questions" to "anon";

grant select on table "app"."quiz_questions" to "anon";

grant update on table "app"."quiz_questions" to "anon";

grant delete on table "app"."quiz_questions" to "authenticated";

grant insert on table "app"."quiz_questions" to "authenticated";

grant select on table "app"."quiz_questions" to "authenticated";

grant update on table "app"."quiz_questions" to "authenticated";

grant delete on table "app"."quiz_questions" to "service_role";

grant insert on table "app"."quiz_questions" to "service_role";

grant select on table "app"."quiz_questions" to "service_role";

grant update on table "app"."quiz_questions" to "service_role";

grant delete on table "app"."referral_codes" to "anon";

grant insert on table "app"."referral_codes" to "anon";

grant select on table "app"."referral_codes" to "anon";

grant update on table "app"."referral_codes" to "anon";

grant delete on table "app"."referral_codes" to "authenticated";

grant insert on table "app"."referral_codes" to "authenticated";

grant select on table "app"."referral_codes" to "authenticated";

grant update on table "app"."referral_codes" to "authenticated";

grant delete on table "app"."referral_codes" to "service_role";

grant insert on table "app"."referral_codes" to "service_role";

grant select on table "app"."referral_codes" to "service_role";

grant update on table "app"."referral_codes" to "service_role";

grant delete on table "app"."refresh_tokens" to "anon";

grant insert on table "app"."refresh_tokens" to "anon";

grant select on table "app"."refresh_tokens" to "anon";

grant update on table "app"."refresh_tokens" to "anon";

grant delete on table "app"."refresh_tokens" to "authenticated";

grant insert on table "app"."refresh_tokens" to "authenticated";

grant select on table "app"."refresh_tokens" to "authenticated";

grant update on table "app"."refresh_tokens" to "authenticated";

grant delete on table "app"."refresh_tokens" to "service_role";

grant insert on table "app"."refresh_tokens" to "service_role";

grant select on table "app"."refresh_tokens" to "service_role";

grant update on table "app"."refresh_tokens" to "service_role";

grant delete on table "app"."reviews" to "anon";

grant insert on table "app"."reviews" to "anon";

grant select on table "app"."reviews" to "anon";

grant update on table "app"."reviews" to "anon";

grant delete on table "app"."reviews" to "authenticated";

grant insert on table "app"."reviews" to "authenticated";

grant select on table "app"."reviews" to "authenticated";

grant update on table "app"."reviews" to "authenticated";

grant delete on table "app"."reviews" to "service_role";

grant insert on table "app"."reviews" to "service_role";

grant select on table "app"."reviews" to "service_role";

grant update on table "app"."reviews" to "service_role";

grant delete on table "app"."runtime_media" to "anon";

grant insert on table "app"."runtime_media" to "anon";

grant select on table "app"."runtime_media" to "anon";

grant update on table "app"."runtime_media" to "anon";

grant delete on table "app"."runtime_media" to "authenticated";

grant insert on table "app"."runtime_media" to "authenticated";

grant select on table "app"."runtime_media" to "authenticated";

grant update on table "app"."runtime_media" to "authenticated";

grant delete on table "app"."runtime_media" to "service_role";

grant insert on table "app"."runtime_media" to "service_role";

grant select on table "app"."runtime_media" to "service_role";

grant update on table "app"."runtime_media" to "service_role";

grant delete on table "app"."seminar_attendees" to "anon";

grant insert on table "app"."seminar_attendees" to "anon";

grant select on table "app"."seminar_attendees" to "anon";

grant update on table "app"."seminar_attendees" to "anon";

grant delete on table "app"."seminar_attendees" to "authenticated";

grant insert on table "app"."seminar_attendees" to "authenticated";

grant select on table "app"."seminar_attendees" to "authenticated";

grant update on table "app"."seminar_attendees" to "authenticated";

grant delete on table "app"."seminar_attendees" to "service_role";

grant insert on table "app"."seminar_attendees" to "service_role";

grant select on table "app"."seminar_attendees" to "service_role";

grant update on table "app"."seminar_attendees" to "service_role";

grant delete on table "app"."seminar_recordings" to "anon";

grant insert on table "app"."seminar_recordings" to "anon";

grant select on table "app"."seminar_recordings" to "anon";

grant update on table "app"."seminar_recordings" to "anon";

grant delete on table "app"."seminar_recordings" to "authenticated";

grant insert on table "app"."seminar_recordings" to "authenticated";

grant select on table "app"."seminar_recordings" to "authenticated";

grant update on table "app"."seminar_recordings" to "authenticated";

grant delete on table "app"."seminar_recordings" to "service_role";

grant insert on table "app"."seminar_recordings" to "service_role";

grant select on table "app"."seminar_recordings" to "service_role";

grant update on table "app"."seminar_recordings" to "service_role";

grant delete on table "app"."seminar_sessions" to "anon";

grant insert on table "app"."seminar_sessions" to "anon";

grant select on table "app"."seminar_sessions" to "anon";

grant update on table "app"."seminar_sessions" to "anon";

grant delete on table "app"."seminar_sessions" to "authenticated";

grant insert on table "app"."seminar_sessions" to "authenticated";

grant select on table "app"."seminar_sessions" to "authenticated";

grant update on table "app"."seminar_sessions" to "authenticated";

grant delete on table "app"."seminar_sessions" to "service_role";

grant insert on table "app"."seminar_sessions" to "service_role";

grant select on table "app"."seminar_sessions" to "service_role";

grant update on table "app"."seminar_sessions" to "service_role";

grant delete on table "app"."seminars" to "anon";

grant insert on table "app"."seminars" to "anon";

grant select on table "app"."seminars" to "anon";

grant update on table "app"."seminars" to "anon";

grant delete on table "app"."seminars" to "authenticated";

grant insert on table "app"."seminars" to "authenticated";

grant select on table "app"."seminars" to "authenticated";

grant update on table "app"."seminars" to "authenticated";

grant delete on table "app"."seminars" to "service_role";

grant insert on table "app"."seminars" to "service_role";

grant select on table "app"."seminars" to "service_role";

grant update on table "app"."seminars" to "service_role";

grant delete on table "app"."services" to "anon";

grant insert on table "app"."services" to "anon";

grant select on table "app"."services" to "anon";

grant update on table "app"."services" to "anon";

grant delete on table "app"."services" to "authenticated";

grant insert on table "app"."services" to "authenticated";

grant select on table "app"."services" to "authenticated";

grant update on table "app"."services" to "authenticated";

grant delete on table "app"."services" to "service_role";

grant insert on table "app"."services" to "service_role";

grant select on table "app"."services" to "service_role";

grant update on table "app"."services" to "service_role";

grant delete on table "app"."session_slots" to "anon";

grant insert on table "app"."session_slots" to "anon";

grant select on table "app"."session_slots" to "anon";

grant update on table "app"."session_slots" to "anon";

grant delete on table "app"."session_slots" to "authenticated";

grant insert on table "app"."session_slots" to "authenticated";

grant select on table "app"."session_slots" to "authenticated";

grant update on table "app"."session_slots" to "authenticated";

grant delete on table "app"."session_slots" to "service_role";

grant insert on table "app"."session_slots" to "service_role";

grant select on table "app"."session_slots" to "service_role";

grant update on table "app"."session_slots" to "service_role";

grant delete on table "app"."sessions" to "anon";

grant insert on table "app"."sessions" to "anon";

grant select on table "app"."sessions" to "anon";

grant update on table "app"."sessions" to "anon";

grant delete on table "app"."sessions" to "authenticated";

grant insert on table "app"."sessions" to "authenticated";

grant select on table "app"."sessions" to "authenticated";

grant update on table "app"."sessions" to "authenticated";

grant delete on table "app"."sessions" to "service_role";

grant insert on table "app"."sessions" to "service_role";

grant select on table "app"."sessions" to "service_role";

grant update on table "app"."sessions" to "service_role";

grant delete on table "app"."stripe_customers" to "anon";

grant insert on table "app"."stripe_customers" to "anon";

grant select on table "app"."stripe_customers" to "anon";

grant update on table "app"."stripe_customers" to "anon";

grant delete on table "app"."stripe_customers" to "authenticated";

grant insert on table "app"."stripe_customers" to "authenticated";

grant select on table "app"."stripe_customers" to "authenticated";

grant update on table "app"."stripe_customers" to "authenticated";

grant delete on table "app"."stripe_customers" to "service_role";

grant insert on table "app"."stripe_customers" to "service_role";

grant select on table "app"."stripe_customers" to "service_role";

grant update on table "app"."stripe_customers" to "service_role";

grant delete on table "app"."subscriptions" to "anon";

grant insert on table "app"."subscriptions" to "anon";

grant select on table "app"."subscriptions" to "anon";

grant update on table "app"."subscriptions" to "anon";

grant delete on table "app"."subscriptions" to "authenticated";

grant insert on table "app"."subscriptions" to "authenticated";

grant select on table "app"."subscriptions" to "authenticated";

grant update on table "app"."subscriptions" to "authenticated";

grant delete on table "app"."subscriptions" to "service_role";

grant insert on table "app"."subscriptions" to "service_role";

grant select on table "app"."subscriptions" to "service_role";

grant update on table "app"."subscriptions" to "service_role";

grant delete on table "app"."tarot_requests" to "anon";

grant insert on table "app"."tarot_requests" to "anon";

grant select on table "app"."tarot_requests" to "anon";

grant update on table "app"."tarot_requests" to "anon";

grant delete on table "app"."tarot_requests" to "authenticated";

grant insert on table "app"."tarot_requests" to "authenticated";

grant select on table "app"."tarot_requests" to "authenticated";

grant update on table "app"."tarot_requests" to "authenticated";

grant delete on table "app"."tarot_requests" to "service_role";

grant insert on table "app"."tarot_requests" to "service_role";

grant select on table "app"."tarot_requests" to "service_role";

grant update on table "app"."tarot_requests" to "service_role";

grant delete on table "app"."teacher_accounts" to "anon";

grant insert on table "app"."teacher_accounts" to "anon";

grant select on table "app"."teacher_accounts" to "anon";

grant update on table "app"."teacher_accounts" to "anon";

grant delete on table "app"."teacher_accounts" to "authenticated";

grant insert on table "app"."teacher_accounts" to "authenticated";

grant select on table "app"."teacher_accounts" to "authenticated";

grant update on table "app"."teacher_accounts" to "authenticated";

grant delete on table "app"."teacher_accounts" to "service_role";

grant insert on table "app"."teacher_accounts" to "service_role";

grant select on table "app"."teacher_accounts" to "service_role";

grant update on table "app"."teacher_accounts" to "service_role";

grant delete on table "app"."teacher_approvals" to "anon";

grant insert on table "app"."teacher_approvals" to "anon";

grant select on table "app"."teacher_approvals" to "anon";

grant update on table "app"."teacher_approvals" to "anon";

grant delete on table "app"."teacher_approvals" to "authenticated";

grant insert on table "app"."teacher_approvals" to "authenticated";

grant select on table "app"."teacher_approvals" to "authenticated";

grant update on table "app"."teacher_approvals" to "authenticated";

grant delete on table "app"."teacher_approvals" to "service_role";

grant insert on table "app"."teacher_approvals" to "service_role";

grant select on table "app"."teacher_approvals" to "service_role";

grant update on table "app"."teacher_approvals" to "service_role";

grant delete on table "app"."teacher_directory" to "anon";

grant insert on table "app"."teacher_directory" to "anon";

grant select on table "app"."teacher_directory" to "anon";

grant update on table "app"."teacher_directory" to "anon";

grant delete on table "app"."teacher_directory" to "authenticated";

grant insert on table "app"."teacher_directory" to "authenticated";

grant select on table "app"."teacher_directory" to "authenticated";

grant update on table "app"."teacher_directory" to "authenticated";

grant delete on table "app"."teacher_directory" to "service_role";

grant insert on table "app"."teacher_directory" to "service_role";

grant select on table "app"."teacher_directory" to "service_role";

grant update on table "app"."teacher_directory" to "service_role";

grant delete on table "app"."teacher_payout_methods" to "anon";

grant insert on table "app"."teacher_payout_methods" to "anon";

grant select on table "app"."teacher_payout_methods" to "anon";

grant update on table "app"."teacher_payout_methods" to "anon";

grant delete on table "app"."teacher_payout_methods" to "authenticated";

grant insert on table "app"."teacher_payout_methods" to "authenticated";

grant select on table "app"."teacher_payout_methods" to "authenticated";

grant update on table "app"."teacher_payout_methods" to "authenticated";

grant delete on table "app"."teacher_payout_methods" to "service_role";

grant insert on table "app"."teacher_payout_methods" to "service_role";

grant select on table "app"."teacher_payout_methods" to "service_role";

grant update on table "app"."teacher_payout_methods" to "service_role";

grant delete on table "app"."teacher_permissions" to "anon";

grant insert on table "app"."teacher_permissions" to "anon";

grant select on table "app"."teacher_permissions" to "anon";

grant update on table "app"."teacher_permissions" to "anon";

grant delete on table "app"."teacher_permissions" to "authenticated";

grant insert on table "app"."teacher_permissions" to "authenticated";

grant select on table "app"."teacher_permissions" to "authenticated";

grant update on table "app"."teacher_permissions" to "authenticated";

grant delete on table "app"."teacher_permissions" to "service_role";

grant insert on table "app"."teacher_permissions" to "service_role";

grant select on table "app"."teacher_permissions" to "service_role";

grant update on table "app"."teacher_permissions" to "service_role";

grant delete on table "app"."teacher_profile_media" to "anon";

grant insert on table "app"."teacher_profile_media" to "anon";

grant select on table "app"."teacher_profile_media" to "anon";

grant update on table "app"."teacher_profile_media" to "anon";

grant delete on table "app"."teacher_profile_media" to "authenticated";

grant insert on table "app"."teacher_profile_media" to "authenticated";

grant select on table "app"."teacher_profile_media" to "authenticated";

grant update on table "app"."teacher_profile_media" to "authenticated";

grant delete on table "app"."teacher_profile_media" to "service_role";

grant insert on table "app"."teacher_profile_media" to "service_role";

grant select on table "app"."teacher_profile_media" to "service_role";

grant update on table "app"."teacher_profile_media" to "service_role";

grant delete on table "app"."teachers" to "anon";

grant insert on table "app"."teachers" to "anon";

grant select on table "app"."teachers" to "anon";

grant update on table "app"."teachers" to "anon";

grant delete on table "app"."teachers" to "authenticated";

grant insert on table "app"."teachers" to "authenticated";

grant select on table "app"."teachers" to "authenticated";

grant update on table "app"."teachers" to "authenticated";

grant delete on table "app"."teachers" to "service_role";

grant insert on table "app"."teachers" to "service_role";

grant select on table "app"."teachers" to "service_role";

grant update on table "app"."teachers" to "service_role";

grant delete on table "app"."welcome_cards" to "anon";

grant insert on table "app"."welcome_cards" to "anon";

grant select on table "app"."welcome_cards" to "anon";

grant update on table "app"."welcome_cards" to "anon";

grant delete on table "app"."welcome_cards" to "authenticated";

grant insert on table "app"."welcome_cards" to "authenticated";

grant select on table "app"."welcome_cards" to "authenticated";

grant update on table "app"."welcome_cards" to "authenticated";

grant delete on table "app"."welcome_cards" to "service_role";

grant insert on table "app"."welcome_cards" to "service_role";

grant select on table "app"."welcome_cards" to "service_role";

grant update on table "app"."welcome_cards" to "service_role";

grant delete on table "public"."coupons" to "anon";

grant insert on table "public"."coupons" to "anon";

grant references on table "public"."coupons" to "anon";

grant select on table "public"."coupons" to "anon";

grant trigger on table "public"."coupons" to "anon";

grant truncate on table "public"."coupons" to "anon";

grant update on table "public"."coupons" to "anon";

grant delete on table "public"."coupons" to "authenticated";

grant insert on table "public"."coupons" to "authenticated";

grant references on table "public"."coupons" to "authenticated";

grant select on table "public"."coupons" to "authenticated";

grant trigger on table "public"."coupons" to "authenticated";

grant truncate on table "public"."coupons" to "authenticated";

grant update on table "public"."coupons" to "authenticated";

grant delete on table "public"."coupons" to "service_role";

grant insert on table "public"."coupons" to "service_role";

grant references on table "public"."coupons" to "service_role";

grant select on table "public"."coupons" to "service_role";

grant trigger on table "public"."coupons" to "service_role";

grant truncate on table "public"."coupons" to "service_role";

grant update on table "public"."coupons" to "service_role";

grant delete on table "public"."subscription_plans" to "anon";

grant insert on table "public"."subscription_plans" to "anon";

grant references on table "public"."subscription_plans" to "anon";

grant select on table "public"."subscription_plans" to "anon";

grant trigger on table "public"."subscription_plans" to "anon";

grant truncate on table "public"."subscription_plans" to "anon";

grant update on table "public"."subscription_plans" to "anon";

grant delete on table "public"."subscription_plans" to "authenticated";

grant insert on table "public"."subscription_plans" to "authenticated";

grant references on table "public"."subscription_plans" to "authenticated";

grant select on table "public"."subscription_plans" to "authenticated";

grant trigger on table "public"."subscription_plans" to "authenticated";

grant truncate on table "public"."subscription_plans" to "authenticated";

grant update on table "public"."subscription_plans" to "authenticated";

grant delete on table "public"."subscription_plans" to "service_role";

grant insert on table "public"."subscription_plans" to "service_role";

grant references on table "public"."subscription_plans" to "service_role";

grant select on table "public"."subscription_plans" to "service_role";

grant trigger on table "public"."subscription_plans" to "service_role";

grant truncate on table "public"."subscription_plans" to "service_role";

grant update on table "public"."subscription_plans" to "service_role";

grant delete on table "public"."subscriptions" to "anon";

grant insert on table "public"."subscriptions" to "anon";

grant references on table "public"."subscriptions" to "anon";

grant select on table "public"."subscriptions" to "anon";

grant trigger on table "public"."subscriptions" to "anon";

grant truncate on table "public"."subscriptions" to "anon";

grant update on table "public"."subscriptions" to "anon";

grant delete on table "public"."subscriptions" to "authenticated";

grant insert on table "public"."subscriptions" to "authenticated";

grant references on table "public"."subscriptions" to "authenticated";

grant select on table "public"."subscriptions" to "authenticated";

grant trigger on table "public"."subscriptions" to "authenticated";

grant truncate on table "public"."subscriptions" to "authenticated";

grant update on table "public"."subscriptions" to "authenticated";

grant delete on table "public"."subscriptions" to "service_role";

grant insert on table "public"."subscriptions" to "service_role";

grant references on table "public"."subscriptions" to "service_role";

grant select on table "public"."subscriptions" to "service_role";

grant trigger on table "public"."subscriptions" to "service_role";

grant truncate on table "public"."subscriptions" to "service_role";

grant update on table "public"."subscriptions" to "service_role";

grant delete on table "public"."user_certifications" to "anon";

grant insert on table "public"."user_certifications" to "anon";

grant references on table "public"."user_certifications" to "anon";

grant select on table "public"."user_certifications" to "anon";

grant trigger on table "public"."user_certifications" to "anon";

grant truncate on table "public"."user_certifications" to "anon";

grant update on table "public"."user_certifications" to "anon";

grant delete on table "public"."user_certifications" to "authenticated";

grant insert on table "public"."user_certifications" to "authenticated";

grant references on table "public"."user_certifications" to "authenticated";

grant select on table "public"."user_certifications" to "authenticated";

grant trigger on table "public"."user_certifications" to "authenticated";

grant truncate on table "public"."user_certifications" to "authenticated";

grant update on table "public"."user_certifications" to "authenticated";

grant delete on table "public"."user_certifications" to "service_role";

grant insert on table "public"."user_certifications" to "service_role";

grant references on table "public"."user_certifications" to "service_role";

grant select on table "public"."user_certifications" to "service_role";

grant trigger on table "public"."user_certifications" to "service_role";

grant truncate on table "public"."user_certifications" to "service_role";

grant update on table "public"."user_certifications" to "service_role";


  create policy "activities_read"
  on "app"."activities"
  as permissive
  for select
  to authenticated
using (true);



  create policy "activities_service"
  on "app"."activities"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."activities"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."app_config"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "auth_events_service"
  on "app"."auth_events"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."auth_events"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "billing_logs_service"
  on "app"."billing_logs"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."billing_logs"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "certificates_service"
  on "app"."certificates"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."certificates"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "classroom_messages_access"
  on "app"."classroom_messages"
  as permissive
  for all
  to authenticated
using (app.has_course_classroom_access(course_id, auth.uid()))
with check (app.has_course_classroom_access(course_id, auth.uid()));



  create policy "classroom_messages_service"
  on "app"."classroom_messages"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "classroom_presence_access"
  on "app"."classroom_presence"
  as permissive
  for all
  to authenticated
using (app.has_course_classroom_access(course_id, auth.uid()))
with check (app.has_course_classroom_access(course_id, auth.uid()));



  create policy "classroom_presence_service"
  on "app"."classroom_presence"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "course_bundle_courses_admin"
  on "app"."course_bundle_courses"
  as permissive
  for all
  to authenticated
using (app.is_admin(auth.uid()))
with check (app.is_admin(auth.uid()));



  create policy "course_bundle_courses_owner"
  on "app"."course_bundle_courses"
  as permissive
  for all
  to public
using ((auth.uid() IN ( SELECT course_bundles.teacher_id
   FROM app.course_bundles
  WHERE (course_bundles.id = course_bundle_courses.bundle_id))))
with check ((auth.uid() IN ( SELECT course_bundles.teacher_id
   FROM app.course_bundles
  WHERE (course_bundles.id = course_bundle_courses.bundle_id))));



  create policy "course_bundle_courses_service_role"
  on "app"."course_bundle_courses"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "course_bundles_admin"
  on "app"."course_bundles"
  as permissive
  for all
  to authenticated
using (app.is_admin(auth.uid()))
with check (app.is_admin(auth.uid()));



  create policy "course_bundles_owner_write"
  on "app"."course_bundles"
  as permissive
  for all
  to public
using ((auth.uid() = teacher_id))
with check ((auth.uid() = teacher_id));



  create policy "course_bundles_public_read"
  on "app"."course_bundles"
  as permissive
  for select
  to public
using ((is_active = true));



  create policy "course_bundles_service_role"
  on "app"."course_bundles"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "course_display_owner"
  on "app"."course_display_priorities"
  as permissive
  for all
  to authenticated
using (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "course_display_service"
  on "app"."course_display_priorities"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."course_display_priorities"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "course_entitlements_owner_read"
  on "app"."course_entitlements"
  as permissive
  for select
  to authenticated
using ((user_id = auth.uid()));



  create policy "course_entitlements_owner_update"
  on "app"."course_entitlements"
  as permissive
  for update
  to authenticated
using ((user_id = auth.uid()))
with check ((user_id = auth.uid()));



  create policy "course_entitlements_self_read"
  on "app"."course_entitlements"
  as permissive
  for select
  to authenticated
using (((user_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "course_entitlements_service_role"
  on "app"."course_entitlements"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."course_entitlements"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "course_products_owner"
  on "app"."course_products"
  as permissive
  for all
  to authenticated
using ((EXISTS ( SELECT 1
   FROM app.courses c
  WHERE ((c.id = course_products.course_id) AND ((c.created_by = auth.uid()) OR app.is_admin(auth.uid()))))))
with check ((EXISTS ( SELECT 1
   FROM app.courses c
  WHERE ((c.id = course_products.course_id) AND ((c.created_by = auth.uid()) OR app.is_admin(auth.uid()))))));



  create policy "course_products_service_role"
  on "app"."course_products"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "quizzes_service"
  on "app"."course_quizzes"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."course_quizzes"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "courses_owner_write"
  on "app"."courses"
  as permissive
  for all
  to authenticated
using (((created_by = auth.uid()) OR app.is_admin(auth.uid())))
with check (((created_by = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "courses_public_read"
  on "app"."courses"
  as permissive
  for select
  to public
using (((is_published = true) OR (created_by = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "courses_service_role"
  on "app"."courses"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."courses"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "enrollments_service"
  on "app"."enrollments"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "enrollments_user"
  on "app"."enrollments"
  as permissive
  for all
  to authenticated
using (((user_id = auth.uid()) OR app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app.courses c
  WHERE ((c.id = enrollments.course_id) AND (c.created_by = auth.uid()))))))
with check (((user_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "service_role_full_access"
  on "app"."enrollments"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "entitlements_service_role"
  on "app"."entitlements"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "entitlements_student"
  on "app"."entitlements"
  as permissive
  for select
  to authenticated
using (((user_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "entitlements_teacher"
  on "app"."entitlements"
  as permissive
  for select
  to authenticated
using ((EXISTS ( SELECT 1
   FROM app.courses c
  WHERE ((c.id = entitlements.course_id) AND ((c.created_by = auth.uid()) OR app.is_admin(auth.uid()))))));



  create policy "event_participants_delete"
  on "app"."event_participants"
  as permissive
  for delete
  to authenticated
using ((app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app.events e
  WHERE ((e.id = event_participants.event_id) AND ((e.created_by = auth.uid()) OR app.is_admin(auth.uid()))))) OR (EXISTS ( SELECT 1
   FROM app.event_participants h
  WHERE ((h.event_id = h.event_id) AND (h.user_id = auth.uid()) AND (h.role = 'host'::app.event_participant_role) AND (h.status <> 'cancelled'::app.event_participant_status))))));



  create policy "event_participants_insert"
  on "app"."event_participants"
  as permissive
  for insert
  to authenticated
with check ((app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app.events e
  WHERE ((e.id = event_participants.event_id) AND ((e.created_by = auth.uid()) OR app.is_admin(auth.uid()))))) OR ((user_id = auth.uid()) AND (role = 'participant'::app.event_participant_role))));



  create policy "event_participants_read"
  on "app"."event_participants"
  as permissive
  for select
  to authenticated
using (((user_id = auth.uid()) OR app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app.events e
  WHERE ((e.id = event_participants.event_id) AND ((e.created_by = auth.uid()) OR app.is_admin(auth.uid()))))) OR (EXISTS ( SELECT 1
   FROM app.event_participants h
  WHERE ((h.event_id = h.event_id) AND (h.user_id = auth.uid()) AND (h.role = 'host'::app.event_participant_role) AND (h.status <> 'cancelled'::app.event_participant_status))))));



  create policy "event_participants_service_role"
  on "app"."event_participants"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "event_participants_update"
  on "app"."event_participants"
  as permissive
  for update
  to authenticated
using ((app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app.events e
  WHERE ((e.id = event_participants.event_id) AND ((e.created_by = auth.uid()) OR app.is_admin(auth.uid()))))) OR (EXISTS ( SELECT 1
   FROM app.event_participants h
  WHERE ((h.event_id = h.event_id) AND (h.user_id = auth.uid()) AND (h.role = 'host'::app.event_participant_role) AND (h.status <> 'cancelled'::app.event_participant_status))))))
with check ((app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app.events e
  WHERE ((e.id = event_participants.event_id) AND ((e.created_by = auth.uid()) OR app.is_admin(auth.uid()))))) OR (EXISTS ( SELECT 1
   FROM app.event_participants h
  WHERE ((h.event_id = h.event_id) AND (h.user_id = auth.uid()) AND (h.role = 'host'::app.event_participant_role) AND (h.status <> 'cancelled'::app.event_participant_status))))));



  create policy "events_owner_rw"
  on "app"."events"
  as permissive
  for all
  to authenticated
using ((((created_by = auth.uid()) AND app.is_teacher(auth.uid())) OR app.is_admin(auth.uid())))
with check ((((created_by = auth.uid()) AND app.is_teacher(auth.uid())) OR app.is_admin(auth.uid())));



  create policy "events_read"
  on "app"."events"
  as permissive
  for select
  to authenticated
using (((created_by = auth.uid()) OR app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app.event_participants ep
  WHERE ((ep.event_id = ep.id) AND (ep.user_id = auth.uid()) AND (ep.status <> 'cancelled'::app.event_participant_status)))) OR ((status <> 'draft'::app.event_status) AND ((visibility = 'public'::app.event_visibility) OR ((visibility = 'members'::app.event_visibility) AND (EXISTS ( SELECT 1
   FROM app.memberships m
  WHERE ((m.user_id = auth.uid()) AND (m.status = 'active'::text) AND ((m.end_date IS NULL) OR (m.end_date > now()))))))))));



  create policy "events_service_role"
  on "app"."events"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "follows_user"
  on "app"."follows"
  as permissive
  for all
  to authenticated
using (((follower_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((follower_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "service_role_full_access"
  on "app"."follows"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "guest_claim_tokens_service_role"
  on "app"."guest_claim_tokens"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "home_player_course_links_owner"
  on "app"."home_player_course_links"
  as permissive
  for all
  to authenticated
using (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "home_player_uploads_owner"
  on "app"."home_player_uploads"
  as permissive
  for all
  to authenticated
using (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "lesson_media_select"
  on "app"."lesson_media"
  as permissive
  for select
  to authenticated
using ((EXISTS ( SELECT 1
   FROM (app.lessons l
     JOIN app.courses c ON ((c.id = l.course_id)))
  WHERE ((l.id = lesson_media.lesson_id) AND ((c.created_by = auth.uid()) OR app.is_admin(auth.uid()) OR (c.is_published AND (l.is_intro = true)) OR (EXISTS ( SELECT 1
           FROM app.enrollments e
          WHERE ((e.course_id = c.id) AND (e.user_id = auth.uid())))))))));



  create policy "lesson_media_service"
  on "app"."lesson_media"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "lesson_media_write"
  on "app"."lesson_media"
  as permissive
  for all
  to authenticated
using ((EXISTS ( SELECT 1
   FROM (app.lessons l
     JOIN app.courses c ON ((c.id = l.course_id)))
  WHERE ((l.id = lesson_media.lesson_id) AND ((c.created_by = auth.uid()) OR app.is_admin(auth.uid()))))))
with check ((EXISTS ( SELECT 1
   FROM (app.lessons l
     JOIN app.courses c ON ((c.id = l.course_id)))
  WHERE ((l.id = lesson_media.lesson_id) AND ((c.created_by = auth.uid()) OR app.is_admin(auth.uid()))))));



  create policy "service_role_full_access"
  on "app"."lesson_media"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "lesson_packages_owner"
  on "app"."lesson_packages"
  as permissive
  for all
  to authenticated
using ((EXISTS ( SELECT 1
   FROM (app.lessons l
     JOIN app.courses c ON ((c.id = l.course_id)))
  WHERE ((l.id = lesson_packages.lesson_id) AND ((c.created_by = auth.uid()) OR app.is_admin(auth.uid()))))))
with check ((EXISTS ( SELECT 1
   FROM (app.lessons l
     JOIN app.courses c ON ((c.id = l.course_id)))
  WHERE ((l.id = lesson_packages.lesson_id) AND ((c.created_by = auth.uid()) OR app.is_admin(auth.uid()))))));



  create policy "lesson_packages_service_role"
  on "app"."lesson_packages"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "lessons_select"
  on "app"."lessons"
  as permissive
  for select
  to authenticated
using ((EXISTS ( SELECT 1
   FROM app.courses c
  WHERE ((c.id = lessons.course_id) AND ((c.created_by = auth.uid()) OR app.is_admin(auth.uid()) OR (c.is_published AND (lessons.is_intro = true)) OR (EXISTS ( SELECT 1
           FROM app.enrollments e
          WHERE ((e.course_id = c.id) AND (e.user_id = auth.uid())))))))));



  create policy "lessons_service_role"
  on "app"."lessons"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "lessons_write"
  on "app"."lessons"
  as permissive
  for all
  to authenticated
using ((EXISTS ( SELECT 1
   FROM app.courses c
  WHERE ((c.id = lessons.course_id) AND ((c.created_by = auth.uid()) OR app.is_admin(auth.uid()))))))
with check ((EXISTS ( SELECT 1
   FROM app.courses c
  WHERE ((c.id = lessons.course_id) AND ((c.created_by = auth.uid()) OR app.is_admin(auth.uid()))))));



  create policy "service_role_full_access"
  on "app"."lessons"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "live_event_registrations_read"
  on "app"."live_event_registrations"
  as permissive
  for select
  to authenticated
using (((user_id = auth.uid()) OR app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app.live_events e
  WHERE ((e.id = live_event_registrations.event_id) AND (e.teacher_id = auth.uid()))))));



  create policy "live_event_registrations_service"
  on "app"."live_event_registrations"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "live_event_registrations_write"
  on "app"."live_event_registrations"
  as permissive
  for all
  to authenticated
using (((user_id = auth.uid()) OR app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app.live_events e
  WHERE ((e.id = live_event_registrations.event_id) AND (e.teacher_id = auth.uid()))))))
with check (((user_id = auth.uid()) OR app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app.live_events e
  WHERE ((e.id = live_event_registrations.event_id) AND (e.teacher_id = auth.uid()))))));



  create policy "service_role_full_access"
  on "app"."live_event_registrations"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "live_events_access"
  on "app"."live_events"
  as permissive
  for select
  to authenticated
using (((teacher_id = auth.uid()) OR app.is_admin(auth.uid()) OR ((is_published = true) AND ((access_type = 'membership'::text) OR ((access_type = 'course'::text) AND (course_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM app.enrollments e
  WHERE ((e.user_id = auth.uid()) AND (e.course_id = live_events.course_id)))))))));



  create policy "live_events_host_rw"
  on "app"."live_events"
  as permissive
  for all
  to authenticated
using (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "live_events_service"
  on "app"."live_events"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."live_events"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "livekit_jobs_service"
  on "app"."livekit_webhook_jobs"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."livekit_webhook_jobs"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "media_owner_rw"
  on "app"."media_objects"
  as permissive
  for all
  to authenticated
using (((owner_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((owner_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "media_service_role"
  on "app"."media_objects"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."media_objects"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "meditations_service"
  on "app"."meditations"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."meditations"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "memberships_self"
  on "app"."memberships"
  as permissive
  for select
  to authenticated
using (((user_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "memberships_service"
  on "app"."memberships"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."memberships"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "messages_user"
  on "app"."messages"
  as permissive
  for all
  to authenticated
using (((sender_id = auth.uid()) OR (recipient_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((sender_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "service_role_full_access"
  on "app"."messages"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "music_tracks_entitled_read"
  on "app"."music_tracks"
  as permissive
  for select
  to authenticated
using (((is_published = true) AND (((access_scope = 'membership'::text) AND (auth.uid() IS NOT NULL) AND ((EXISTS ( SELECT 1
   FROM app.memberships m
  WHERE ((m.user_id = auth.uid()) AND (lower(COALESCE(m.status, 'active'::text)) <> ALL (ARRAY['canceled'::text, 'unpaid'::text, 'incomplete_expired'::text, 'past_due'::text]))))) OR true)) OR ((access_scope = 'course'::text) AND (course_id IS NOT NULL) AND app.has_course_classroom_access(course_id, auth.uid())))));



  create policy "music_tracks_owner"
  on "app"."music_tracks"
  as permissive
  for all
  to authenticated
using (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "music_tracks_service"
  on "app"."music_tracks"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "notification_audiences_owner_rw"
  on "app"."notification_audiences"
  as permissive
  for all
  to authenticated
using ((EXISTS ( SELECT 1
   FROM app.notification_campaigns n
  WHERE ((n.id = notification_audiences.notification_id) AND (((n.created_by = auth.uid()) AND app.is_teacher(auth.uid())) OR app.is_admin(auth.uid()))))))
with check ((EXISTS ( SELECT 1
   FROM app.notification_campaigns n
  WHERE ((n.id = notification_audiences.notification_id) AND (((n.created_by = auth.uid()) AND app.is_teacher(auth.uid())) OR app.is_admin(auth.uid()))))));



  create policy "notification_audiences_service_role"
  on "app"."notification_audiences"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "notification_campaigns_owner_rw"
  on "app"."notification_campaigns"
  as permissive
  for all
  to authenticated
using ((((created_by = auth.uid()) AND app.is_teacher(auth.uid())) OR app.is_admin(auth.uid())))
with check ((((created_by = auth.uid()) AND app.is_teacher(auth.uid())) OR app.is_admin(auth.uid())));



  create policy "notification_campaigns_service_role"
  on "app"."notification_campaigns"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "notification_deliveries_delete"
  on "app"."notification_deliveries"
  as permissive
  for delete
  to authenticated
using ((EXISTS ( SELECT 1
   FROM app.notification_campaigns n
  WHERE ((n.id = notification_deliveries.notification_id) AND (((n.created_by = auth.uid()) AND app.is_teacher(auth.uid())) OR app.is_admin(auth.uid()))))));



  create policy "notification_deliveries_insert"
  on "app"."notification_deliveries"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM app.notification_campaigns n
  WHERE ((n.id = notification_deliveries.notification_id) AND (((n.created_by = auth.uid()) AND app.is_teacher(auth.uid())) OR app.is_admin(auth.uid()))))));



  create policy "notification_deliveries_read"
  on "app"."notification_deliveries"
  as permissive
  for select
  to authenticated
using (((user_id = auth.uid()) OR app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app.notification_campaigns n
  WHERE ((n.id = notification_deliveries.notification_id) AND ((n.created_by = auth.uid()) OR app.is_admin(auth.uid())))))));



  create policy "notification_deliveries_service_role"
  on "app"."notification_deliveries"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "notification_deliveries_update"
  on "app"."notification_deliveries"
  as permissive
  for update
  to authenticated
using ((EXISTS ( SELECT 1
   FROM app.notification_campaigns n
  WHERE ((n.id = notification_deliveries.notification_id) AND (((n.created_by = auth.uid()) AND app.is_teacher(auth.uid())) OR app.is_admin(auth.uid()))))))
with check ((EXISTS ( SELECT 1
   FROM app.notification_campaigns n
  WHERE ((n.id = notification_deliveries.notification_id) AND (((n.created_by = auth.uid()) AND app.is_teacher(auth.uid())) OR app.is_admin(auth.uid()))))));



  create policy "notifications_user"
  on "app"."notifications"
  as permissive
  for all
  to authenticated
using (((user_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((user_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "service_role_full_access"
  on "app"."notifications"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "orders_service"
  on "app"."orders"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "orders_user_read"
  on "app"."orders"
  as permissive
  for select
  to authenticated
using (((user_id = auth.uid()) OR app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app.services s
  WHERE ((s.id = orders.service_id) AND (s.provider_id = auth.uid()))))));



  create policy "orders_user_write"
  on "app"."orders"
  as permissive
  for insert
  to authenticated
with check (((user_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "service_role_full_access"
  on "app"."orders"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "payment_events_service"
  on "app"."payment_events"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."payment_events"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "payments_read"
  on "app"."payments"
  as permissive
  for select
  to authenticated
using ((EXISTS ( SELECT 1
   FROM app.orders o
  WHERE ((o.id = payments.order_id) AND ((o.user_id = auth.uid()) OR app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
           FROM app.services s
          WHERE ((s.id = o.service_id) AND (s.provider_id = auth.uid())))))))));



  create policy "payments_service"
  on "app"."payments"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."payments"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "posts_author"
  on "app"."posts"
  as permissive
  for all
  to authenticated
using (((author_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((author_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "posts_service"
  on "app"."posts"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."posts"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "profiles_self_read"
  on "app"."profiles"
  as permissive
  for select
  to public
using (((auth.uid() = user_id) OR app.is_admin(auth.uid())));



  create policy "profiles_self_write"
  on "app"."profiles"
  as permissive
  for update
  to authenticated
using (((auth.uid() = user_id) OR app.is_admin(auth.uid())))
with check (((auth.uid() = user_id) OR app.is_admin(auth.uid())));



  create policy "service_role_full_access"
  on "app"."profiles"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "purchases_owner_read"
  on "app"."purchases"
  as permissive
  for select
  to authenticated
using ((user_id = auth.uid()));



  create policy "purchases_service_role"
  on "app"."purchases"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "quiz_questions_service"
  on "app"."quiz_questions"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."quiz_questions"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "refresh_tokens_service"
  on "app"."refresh_tokens"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."refresh_tokens"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "reviews_service"
  on "app"."reviews"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "reviews_user"
  on "app"."reviews"
  as permissive
  for all
  to authenticated
using (((reviewer_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((reviewer_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "service_role_full_access"
  on "app"."reviews"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "attendees_read"
  on "app"."seminar_attendees"
  as permissive
  for select
  to authenticated
using (((user_id = auth.uid()) OR app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app.seminars s
  WHERE ((s.id = seminar_attendees.seminar_id) AND (s.host_id = auth.uid()))))));



  create policy "attendees_service"
  on "app"."seminar_attendees"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "attendees_write"
  on "app"."seminar_attendees"
  as permissive
  for all
  to authenticated
using (((user_id = auth.uid()) OR app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app.seminars s
  WHERE ((s.id = seminar_attendees.seminar_id) AND (s.host_id = auth.uid()))))))
with check (((user_id = auth.uid()) OR app.is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app.seminars s
  WHERE ((s.id = seminar_attendees.seminar_id) AND (s.host_id = auth.uid()))))));



  create policy "service_role_full_access"
  on "app"."seminar_attendees"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "seminar_recordings_read"
  on "app"."seminar_recordings"
  as permissive
  for select
  to authenticated
using ((EXISTS ( SELECT 1
   FROM app.seminars s
  WHERE ((s.id = seminar_recordings.seminar_id) AND ((s.host_id = auth.uid()) OR app.is_admin(auth.uid()) OR (s.status = ANY (ARRAY['live'::app.seminar_status, 'ended'::app.seminar_status])))))));



  create policy "seminar_recordings_service"
  on "app"."seminar_recordings"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."seminar_recordings"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "seminar_sessions_host"
  on "app"."seminar_sessions"
  as permissive
  for all
  to authenticated
using ((EXISTS ( SELECT 1
   FROM app.seminars s
  WHERE ((s.id = seminar_sessions.seminar_id) AND ((s.host_id = auth.uid()) OR app.is_admin(auth.uid()))))))
with check ((EXISTS ( SELECT 1
   FROM app.seminars s
  WHERE ((s.id = seminar_sessions.seminar_id) AND ((s.host_id = auth.uid()) OR app.is_admin(auth.uid()))))));



  create policy "seminar_sessions_service"
  on "app"."seminar_sessions"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."seminar_sessions"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "seminars_host_rw"
  on "app"."seminars"
  as permissive
  for all
  to authenticated
using (((host_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((host_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "seminars_public_read"
  on "app"."seminars"
  as permissive
  for select
  to public
using (((status = ANY (ARRAY['scheduled'::app.seminar_status, 'live'::app.seminar_status, 'ended'::app.seminar_status])) OR (host_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "seminars_service"
  on "app"."seminars"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."seminars"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."services"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "services_owner_rw"
  on "app"."services"
  as permissive
  for all
  to authenticated
using (((provider_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((provider_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "services_public_read"
  on "app"."services"
  as permissive
  for select
  to public
using (((status = 'active'::app.service_status) AND (active = true)));



  create policy "services_service"
  on "app"."services"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."session_slots"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "session_slots_owner"
  on "app"."session_slots"
  as permissive
  for all
  to authenticated
using ((EXISTS ( SELECT 1
   FROM app.sessions s
  WHERE ((s.id = session_slots.session_id) AND ((s.teacher_id = auth.uid()) OR app.is_admin(auth.uid()))))))
with check ((EXISTS ( SELECT 1
   FROM app.sessions s
  WHERE ((s.id = session_slots.session_id) AND ((s.teacher_id = auth.uid()) OR app.is_admin(auth.uid()))))));



  create policy "session_slots_service"
  on "app"."session_slots"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."sessions"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "sessions_owner"
  on "app"."sessions"
  as permissive
  for all
  to authenticated
using (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "sessions_public_read"
  on "app"."sessions"
  as permissive
  for select
  to public
using (((visibility = 'published'::app.session_visibility) OR (teacher_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "sessions_service"
  on "app"."sessions"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."stripe_customers"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "stripe_customers_service"
  on "app"."stripe_customers"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "subscriptions_self_read"
  on "app"."subscriptions"
  as permissive
  for select
  to authenticated
using (((user_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "subscriptions_service_role"
  on "app"."subscriptions"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."tarot_requests"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "tarot_service"
  on "app"."tarot_requests"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "teacher_accounts_self"
  on "app"."teacher_accounts"
  as permissive
  for all
  to authenticated
using (((auth.uid() = user_id) OR app.is_admin(auth.uid())))
with check (((auth.uid() = user_id) OR app.is_admin(auth.uid())));



  create policy "teacher_accounts_service_role"
  on "app"."teacher_accounts"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."teacher_approvals"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "teacher_approvals_service"
  on "app"."teacher_approvals"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."teacher_directory"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "teacher_directory_service"
  on "app"."teacher_directory"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "payout_service"
  on "app"."teacher_payout_methods"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "payout_teacher"
  on "app"."teacher_payout_methods"
  as permissive
  for all
  to authenticated
using (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "service_role_full_access"
  on "app"."teacher_payout_methods"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."teacher_permissions"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "teacher_meta_service"
  on "app"."teacher_permissions"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."teacher_profile_media"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "tpm_public_read"
  on "app"."teacher_profile_media"
  as permissive
  for select
  to public
using ((is_published = true));



  create policy "tpm_teacher"
  on "app"."teacher_profile_media"
  as permissive
  for all
  to authenticated
using (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "service_role_full_access"
  on "app"."teachers"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "teachers_owner"
  on "app"."teachers"
  as permissive
  for all
  to authenticated
using (((profile_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((profile_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "teachers_service"
  on "app"."teachers"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "welcome_cards_active_read"
  on "app"."welcome_cards"
  as permissive
  for select
  to authenticated
using ((is_active = true));



  create policy "welcome_cards_manage"
  on "app"."welcome_cards"
  as permissive
  for all
  to authenticated
using ((((created_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM app.profiles p
  WHERE ((p.user_id = auth.uid()) AND ((p.role_v2 = 'teacher'::app.user_role) OR (p.is_admin = true)))))) OR app.is_admin(auth.uid())))
with check ((((created_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM app.profiles p
  WHERE ((p.user_id = auth.uid()) AND ((p.role_v2 = 'teacher'::app.user_role) OR (p.is_admin = true)))))) OR app.is_admin(auth.uid())));



  create policy "welcome_cards_owner_read"
  on "app"."welcome_cards"
  as permissive
  for select
  to authenticated
using ((((created_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM app.profiles p
  WHERE ((p.user_id = auth.uid()) AND ((p.role_v2 = 'teacher'::app.user_role) OR (p.is_admin = true)))))) OR app.is_admin(auth.uid())));



  create policy "welcome_cards_service_role"
  on "app"."welcome_cards"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "coupons_service_role"
  on "public"."coupons"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "subscription_plans_public_read"
  on "public"."subscription_plans"
  as permissive
  for select
  to public
using ((is_active = true));



  create policy "subscription_plans_service_role"
  on "public"."subscription_plans"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "public_subscriptions_self_read"
  on "public"."subscriptions"
  as permissive
  for select
  to authenticated
using (((user_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "public_subscriptions_service_role"
  on "public"."subscriptions"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "user_certifications_self_read"
  on "public"."user_certifications"
  as permissive
  for select
  to authenticated
using (((user_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "user_certifications_service_role"
  on "public"."user_certifications"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));


CREATE TRIGGER trg_course_display_priorities_touch BEFORE UPDATE ON app.course_display_priorities FOR EACH ROW EXECUTE FUNCTION app.touch_course_display_priorities();

CREATE TRIGGER trg_course_entitlements_touch BEFORE UPDATE ON app.course_entitlements FOR EACH ROW EXECUTE FUNCTION app.touch_course_entitlements();

CREATE TRIGGER trg_course_products_updated BEFORE UPDATE ON app.course_products FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_courses_touch BEFORE UPDATE ON app.courses FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_runtime_media_sync_course_context AFTER UPDATE OF created_by ON app.courses FOR EACH ROW EXECUTE FUNCTION app.sync_runtime_media_course_context_trigger();

CREATE TRIGGER trg_events_status_progression BEFORE UPDATE OF status ON app.events FOR EACH ROW EXECUTE FUNCTION app.enforce_event_status_progression();

CREATE TRIGGER trg_events_touch BEFORE UPDATE ON app.events FOR EACH ROW EXECUTE FUNCTION app.touch_events();

CREATE TRIGGER trg_home_player_course_links_touch BEFORE UPDATE ON app.home_player_course_links FOR EACH ROW EXECUTE FUNCTION app.touch_home_player_course_links();

CREATE TRIGGER trg_home_player_uploads_touch BEFORE UPDATE ON app.home_player_uploads FOR EACH ROW EXECUTE FUNCTION app.touch_home_player_uploads();

CREATE TRIGGER trg_intro_usage_touch BEFORE UPDATE ON app.intro_usage FOR EACH ROW EXECUTE FUNCTION app.touch_intro_usage();

CREATE TRIGGER trg_runtime_media_sync_lesson_media AFTER INSERT OR UPDATE OF lesson_id, kind, media_id, storage_path, storage_bucket, media_asset_id ON app.lesson_media FOR EACH ROW EXECUTE FUNCTION app.sync_runtime_media_lesson_media_trigger();

CREATE TRIGGER trg_lesson_packages_updated BEFORE UPDATE ON app.lesson_packages FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_lessons_touch BEFORE UPDATE ON app.lessons FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_runtime_media_sync_lesson_context AFTER UPDATE OF course_id ON app.lessons FOR EACH ROW EXECUTE FUNCTION app.sync_runtime_media_lesson_context_trigger();

CREATE TRIGGER trg_live_events_touch BEFORE UPDATE ON app.live_events FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_livekit_webhook_jobs_touch BEFORE UPDATE ON app.livekit_webhook_jobs FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_music_tracks_updated_at BEFORE UPDATE ON app.music_tracks FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_orders_touch BEFORE UPDATE ON app.orders FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_payments_touch BEFORE UPDATE ON app.payments FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_profiles_touch BEFORE UPDATE ON app.profiles FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_runtime_media_touch BEFORE UPDATE ON app.runtime_media FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_seminar_recordings_touch BEFORE UPDATE ON app.seminar_recordings FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_seminar_sessions_touch BEFORE UPDATE ON app.seminar_sessions FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_seminars_touch BEFORE UPDATE ON app.seminars FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_services_touch BEFORE UPDATE ON app.services FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_session_slots_touch BEFORE UPDATE ON app.session_slots FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_sessions_touch BEFORE UPDATE ON app.sessions FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_subscriptions_touch BEFORE UPDATE ON app.subscriptions FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_teacher_accounts_updated BEFORE UPDATE ON app.teacher_accounts FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_teacher_approvals_touch BEFORE UPDATE ON app.teacher_approvals FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_teacher_payout_methods_touch BEFORE UPDATE ON app.teacher_payout_methods FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_teacher_profile_media_touch BEFORE UPDATE ON app.teacher_profile_media FOR EACH ROW EXECUTE FUNCTION app.touch_teacher_profile_media();

CREATE TRIGGER trg_teachers_touch BEFORE UPDATE ON app.teachers FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_welcome_cards_updated_at BEFORE UPDATE ON app.welcome_cards FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_coupons_touch BEFORE UPDATE ON public.coupons FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_subscription_plans_touch BEFORE UPDATE ON public.subscription_plans FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_public_subscriptions_touch BEFORE UPDATE ON public.subscriptions FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


  create policy "storage_owner_private_rw"
  on "storage"."objects"
  as permissive
  for all
  to authenticated
using (((bucket_id = ANY (ARRAY['course-media'::text, 'lesson-media'::text, 'audio_private'::text, 'welcome-cards'::text])) AND (owner = auth.uid())))
with check (((bucket_id = ANY (ARRAY['course-media'::text, 'lesson-media'::text, 'audio_private'::text, 'welcome-cards'::text])) AND (owner = auth.uid())));



  create policy "storage_public_read_avatars_thumbnails"
  on "storage"."objects"
  as permissive
  for select
  to public
using ((bucket_id = ANY (ARRAY['avatars'::text, 'thumbnails'::text])));



  create policy "storage_service_role_full_access"
  on "storage"."objects"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "storage_signed_private_read"
  on "storage"."objects"
  as permissive
  for select
  to authenticated
using ((bucket_id = ANY (ARRAY['course-media'::text, 'lesson-media'::text, 'audio_private'::text, 'welcome-cards'::text])));



