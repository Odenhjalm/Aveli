# Replayability Fail Points

## P0 (crash on fresh DB)

1) Missing live_events tables
- File: supabase/migrations/20260102113500_live_events_rls.sql:6-7
- Failing SQL:
  - `alter table app.live_events enable row level security;`
  - `alter table app.live_event_registrations enable row level security;`
- Why: app.live_events and app.live_event_registrations are never created in local migrations, so a fresh replay fails immediately.
- Recommended fix: add a migration that creates these tables before RLS or guard this migration with to_regclass and move policies after table creation.

## P1 (environment-dependent crash)

1) Storage buckets require storage schema
- Files:
  - supabase/migrations/018_storage_buckets.sql:4-13
  - supabase/migrations/20260102113600_storage_public_media.sql:6-16
- Failing SQL: `insert into storage.buckets (id, name, public) values ('public-media', 'public-media', true)`
- Why: storage.buckets does not exist on a plain Postgres instance without Supabase Storage installed.
- Recommended fix: ensure storage extension is installed before migrations, or guard with to_regclass('storage.buckets').

## P2 (runner/transaction-dependent crash)

1) ALTER TYPE add value inside a transaction
- File: supabase/migrations/017_order_type_bundle.sql:1
- Failing SQL: `alter type app.order_type add value if not exists 'bundle';`
- Why: `ALTER TYPE ... ADD VALUE` is not transaction-safe in some Postgres versions/runner modes; migration runners that wrap files in a transaction can fail here.
- Recommended fix: run this migration outside a transaction or isolate it as a no-transaction migration.

2) Extension creation requires elevated privileges
- File: supabase/migrations/001_app_schema.sql:12-13
- Failing SQL:
  - `create extension if not exists pgcrypto;`
  - `create extension if not exists "uuid-ossp";`
- Why: extension creation requires superuser rights in some environments.
- Recommended fix: pre-install extensions at the platform level or ensure migration role has privileges.
