# Rebuild Plan (Replayable Supabase Migrations)

## Goals
- Deterministic, replayable local schema without relying on remote drift.
- Clear ordering: schema -> tables -> functions/triggers -> RLS enablement -> policies.
- Preserve old migrations for history; new migrations add or supersede behavior.

## Option A: Minimal Intervention (add new baseline migrations)

### Steps
1) Add a post-create LiveKit normalization migration (new timestamped file after 20251215090200).
   - Rename `job_id -> id`, `attempts -> attempt`, `error -> last_error`, `last_attempted_at -> last_attempt_at`.
   - Add `next_run_at` if missing; set defaults and not-null; ensure trigger uses the expected touch function.
   - This fixes the backend expectations for `livekit_webhook_jobs` without editing old files.

2) Add a late-table RLS baseline migration (promote `_pending_local/20260110_90000_rls_baseline_late_tables.sql` to a new timestamped root migration).
   - Enable RLS and add service_role policies for `seminar_sessions`, `seminar_recordings`, `livekit_webhook_jobs` after those tables exist.

3) Resolve missing live_events tables before `20260102113500_live_events_rls.sql`.
   - Create new migrations that define `app.live_events` and `app.live_event_registrations` (exact schema must be sourced from product requirements or a future `supabase db pull` run).
   - Alternatively, wrap `20260102113500_live_events_rls.sql` in a guard so it can run safely after creation.

4) Add missing backend objects to migrations.
   - `app.subscriptions` (table) and `app.grade_quiz_and_issue_certificate` (function) are referenced by backend code but are absent in migrations.
   - Define these objects in new timestamped migrations after core tables and functions.

5) Storage buckets and policies.
   - Keep one idempotent bucket migration (upsert style). Ensure it runs after storage schema exists.
   - Add explicit `storage.objects` policies (audit notes indicate none are present) if storage access is required.

6) Remote-only drift items (from audit + drift marker comment).
   - The drift marker references: course_entitlements_and_storage_policies, fix_purchases_and_claim_tokens, aveli_pro_platform, lesson_pricing, live_events, auth_profile_provider_columns, 027_classroom, 028_media_library, 029_welcome_cards.
   - Create migrations for each confirmed object or add a tracking note until a DB pull is performed.

### Pros
- Minimal disruption; no rewrite of existing migrations.
- Low risk for existing environments because changes are additive.
- Keeps history intact and aligns with current deployment flow.

### Cons
- Legacy ordering issues remain; fixes are layered on top.
- Still depends on drift marker awareness for missing remote-only objects.
- Long-term maintenance burden (mixed naming schemes).

### Risk
- Medium: functionality and security can still drift if new tables are added without post-create RLS/policy migrations.

### Cutover Steps
1) Add new timestamped migrations in `supabase/migrations/`.
2) Run local replay (e.g., `supabase db reset`) to validate end-to-end ordering (no remote writes).
3) Apply new migrations to non-prod environments; confirm LiveKit job and seminar session flows.
4) Roll out to production via standard migration pipeline.

## Option B: Clean Rebuild (new v2 migration chain)

### Steps
1) Create a new chain in `supabase/migrations_v2/` (keeps old migrations untouched).
   - 0001_app_schema.sql: extensions, schemas, enums.
   - 0002_tables_core.sql: profiles, courses, modules, lessons, orders, services, payments, etc.
   - 0003_tables_extended.sql: livekit_webhook_jobs (with correct columns), seminar_sessions/recordings, course_bundles, purchases/entitlements/guest_claim_tokens/course_products, memberships, etc.
   - 0004_functions_triggers.sql: app.set_updated_at, seminar helpers, touch functions, triggers.
   - 0005_rls_base.sql: enable RLS after all tables exist.
   - 0006_policies.sql: policies per table.

2) Include missing backend objects and drift-only items in v2.
   - `app.subscriptions`, `app.grade_quiz_and_issue_certificate`, and any confirmed remote-only tables/functions (from drift marker list or future DB pull).

3) Storage buckets and policies.
   - Define buckets once and add explicit storage policies in v2.

4) Standardize naming and ordering.
   - Use only 4-digit series files inside v2 or full timestamps; avoid date-only prefixes.

### Pros
- Fully deterministic, replayable schema with clear ordering.
- Easier to reason about dependencies and RLS sequencing.
- Eliminates reliance on drift markers.

### Cons
- Requires a migration cutover plan and possible data backfill.
- Higher upfront effort and coordination.

### Risk
- Medium-to-high: new chain requires validation and data migration if replacing existing DBs.

### Cutover Steps
1) Build v2 migrations in `supabase/migrations_v2/` and validate with a full local reset.
2) Create a new database (or a fresh schema) and apply v2 migrations.
3) Data migration: export from current DB and import into v2 schema, validating critical flows.
4) Update deployment config to use v2 for new environments; keep old migrations for history.
5) Switch application connection to the new DB once parity is confirmed.

## Object-Specific Coverage (Required)
- live_events/live_event_registrations: add table definitions before RLS; do not leave only the policy migration.
- livekit_webhook_jobs: ensure columns match backend (id, attempt, last_error, last_attempt_at, next_run_at) and RLS is applied after table creation.
- seminar_sessions/seminar_recordings: create tables before RLS and ensure policies are applied after creation.
- purchases/entitlements/guest_claim_tokens/course_products: keep table creation before RLS policies; use triggers after app.set_updated_at exists.
- storage buckets: keep a single idempotent bucket migration and add explicit storage policies if required.
- remote-only audit items: reconcile drift marker list into actual migrations; avoid relying on schema_migrations-only entries.
