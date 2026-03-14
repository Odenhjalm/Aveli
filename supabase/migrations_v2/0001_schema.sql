-- 0001_schema.sql
-- Schema primitives for the v2 baseline.

begin;

create extension if not exists pgcrypto;
create extension if not exists "uuid-ossp";

create schema if not exists auth;
create schema if not exists app;

-- ---------------------------------------------------------------------------
-- Enumerated types
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

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'session_visibility'
      and n.nspname = 'app'
  ) then
    create type app.session_visibility as enum ('draft', 'published');
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'order_type'
      and n.nspname = 'app'
  ) then
    create type app.order_type as enum ('one_off', 'subscription', 'bundle');
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'seminar_session_status'
      and n.nspname = 'app'
  ) then
    create type app.seminar_session_status as enum ('scheduled', 'live', 'ended', 'failed');
  end if;
end$$;

commit;
