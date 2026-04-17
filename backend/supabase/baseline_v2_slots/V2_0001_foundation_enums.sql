create schema if not exists app;

create type app.auth_subject_role as enum (
  'learner',
  'teacher',
  'admin'
);

create type app.onboarding_state as enum (
  'incomplete',
  'welcome_pending',
  'completed'
);

create type app.course_visibility as enum (
  'draft',
  'private',
  'public'
);

create type app.course_enrollment_source as enum (
  'purchase',
  'intro_enrollment'
);

create type app.profile_media_visibility as enum (
  'draft',
  'published'
);

create type app.media_type as enum (
  'audio',
  'image',
  'video',
  'document'
);

create type app.media_purpose as enum (
  'course_cover',
  'lesson_media',
  'home_player_audio',
  'profile_media'
);

create type app.media_state as enum (
  'pending_upload',
  'uploaded',
  'processing',
  'ready',
  'failed'
);

create type app.order_type as enum (
  'one_off',
  'subscription',
  'bundle'
);

create type app.order_status as enum (
  'pending',
  'requires_action',
  'processing',
  'paid',
  'canceled',
  'failed',
  'refunded'
);

create type app.payment_status as enum (
  'pending',
  'processing',
  'paid',
  'failed',
  'refunded'
);

create type app.membership_status as enum (
  'inactive',
  'active',
  'past_due',
  'canceled',
  'expired'
);

create type app.membership_source as enum (
  'purchase',
  'coupon',
  'referral'
);
