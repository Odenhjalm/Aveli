-- Phase 1: canonical schema foundation
-- Clean-room inputs only:
-- - AVELI_COURSE_DOMAIN_SPEC.md
-- - Aveli_System_Decisions.md
-- - aveli_system_manifest.json
-- - AVELI_DATABASE_BASELINE_MANIFEST.md
-- Scope:
-- - app schema preconditions
-- - canonical enums only
-- - no shared immutable helpers unless explicitly required by canonical laws
-- - no business tables
-- - no legacy compatibility behavior
-- External dependencies remain soft references only:
-- - auth.users
-- - storage.objects
-- - storage.buckets

create schema if not exists app;

create type app.course_step as enum (
  'intro',
  'step1',
  'step2',
  'step3'
);

create type app.course_enrollment_source as enum (
  'purchase',
  'intro_enrollment'
);

create type app.media_type as enum (
  'audio',
  'image',
  'video',
  'document'
);

create type app.media_purpose as enum (
  'course_cover',
  'lesson_media'
);

create type app.media_state as enum (
  'pending_upload',
  'uploaded',
  'processing',
  'ready',
  'failed'
);
