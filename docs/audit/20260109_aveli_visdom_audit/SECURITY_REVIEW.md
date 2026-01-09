# Security Review (Phase 2)

## Sources
- Auth + JWT: `backend/app/auth.py`, `backend/app/routes/api_auth.py`, `backend/app/permissions.py`, `backend/app/models.py`, `backend/app/config.py`.
- RLS policies: `supabase/migrations/007_rls_policies.sql`, `supabase/migrations/008_rls_app_policies.sql`, `supabase/migrations/016_course_bundles.sql`, `supabase/migrations/20260102113500_live_events_rls.sql`.
- Storage buckets: `supabase/migrations/018_storage_buckets.sql`, `supabase/migrations/20260102113600_storage_public_media.sql`.
- Security definer functions: `supabase/security_definer_export.sql`.
Note: snapshot CSVs (`rls_policies.csv`, `storage_policies.csv`, `grants.csv`, `functions.csv`) were not present in the workspace, so the analysis uses migrations and `security_definer_export.sql`.

## Auth & JWT
- **JWT validation**: `backend/app/auth.py` uses `decode_jwt()` with signature verification but disables exp verification, then enforces expiry via `is_token_expired()`; access tokens must have `token_type='access'` and `sub`. (`backend/app/auth.py`)
- **Access token claims**: `api_auth` builds claims `{role,is_admin,is_teacher}` via `_claims_for_user()`; role derives from `profiles.role_v2`, admin via `profiles.is_admin`, teacher via `models.is_teacher_user()`. (`backend/app/routes/api_auth.py`, `backend/app/models.py`)
- **Refresh flow (active)**: `/auth/refresh` in `api_auth` validates refresh JWT, checks `app.refresh_tokens` for jti + token hash, rotates token, and logs auth events. (`backend/app/routes/api_auth.py`, `backend/app/repositories/auth.py`)
- **Role enforcement**: `permissions.TeacherUser`/`AdminUser` depend on `models.is_teacher_user` / `models.is_admin_user`. (`backend/app/permissions.py`, `backend/app/models.py`)
- **Config defaults**: `jwt_secret` default is `"change-me"`; `jwt_expires_minutes` default 15, refresh 24h. (`backend/app/config.py`)

**Mounted vs legacy auth:** Only `api_auth.router` is included in `backend/app/main.py`; `backend/app/routes/auth.py` (rate-limited variant) is not mounted. This is a drift risk if clients/ops expect those endpoints. (see `backend/app/main.py`, `backend/app/routes/auth.py`)

## RLS & Policy Findings
See `RLS_MATRIX.md` for full policy table. Key findings derived from migrations:
- **RLS missing**: `app.course_entitlements` is created but never `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` in migrations. (source: `supabase/migrations/005_course_entitlements.sql`, `RLS_MATRIX.md` summary)
- **Only service_role policies**: Several tables only have service-role policies (no user-facing policy), including `app.auth_events`, `app.refresh_tokens`, `app.teacher_permissions`, `app.teacher_approvals`, `app.teacher_directory`, `app.stripe_customers`, `app.course_quizzes`, `app.quiz_questions`, `app.meditations`, `app.tarot_requests`, `app.payment_events`, `app.billing_logs`, `app.livekit_webhook_jobs`. (source: `supabase/migrations/007_rls_policies.sql`, `supabase/migrations/008_rls_app_policies.sql`)
- **Allow-all policy**: `app.activities` has `activities_read` policy `using (true)` for authenticated. (`supabase/migrations/008_rls_app_policies.sql`)
- **Public read policies**: `app.courses`, `app.services`, `app.seminars`, `app.sessions`, `app.teacher_profile_media` include explicit public-read policies with additional conditions. (`supabase/migrations/008_rls_app_policies.sql`)

## Storage
- Buckets defined in migrations: `public-media` (public), `course-media` (private), `lesson-media` (private). (`supabase/migrations/018_storage_buckets.sql`, `supabase/migrations/20260102113600_storage_public_media.sql`)
- **No storage policies in migrations**: No `storage.objects` policies are present in migration files; without snapshot CSVs, current policy state can’t be verified. (source: migrations scan)

## Security Definer Functions
Found in `supabase/security_definer_export.sql`:
- **app.***: `app.can_access_seminar`, `app.is_seminar_attendee`, `app.is_seminar_host` — SECURITY DEFINER, STABLE. These guard access for non-service roles and allow service role to pass `p_user_id` (explicit checks present). (source: `supabase/security_definer_export.sql`)
- **storage.***: `storage.add_prefixes`, `storage.delete_leaf_prefixes`, `storage.delete_prefix`, `storage.lock_top_prefixes`, `storage.objects_*_cleanup`, `storage.prefixes_delete_cleanup` — standard Supabase storage internals.
- **pgbouncer.get_auth** — SECURITY DEFINER, returns auth credentials (requires strict grants).
- **vault.create_secret / vault.update_secret** — SECURITY DEFINER (requires strict grants).
- **graphql.get_schema_version / graphql.increment_schema_version** — SECURITY DEFINER (system usage).

## Top 10 Security Risks (with fixes)
1. **`app.course_entitlements` has RLS disabled** — risk of direct table access if exposed. Enable RLS and add policies for owner/service roles. (`supabase/migrations/005_course_entitlements.sql`)
2. **Storage policies not tracked in migrations** — no `storage.objects` policies defined; risk of accidental public exposure or overly restrictive access depending on DB state. Add explicit storage policies and track in migrations. (`supabase/migrations/018_storage_buckets.sql`)
3. **Dual auth implementations** (mounted `api_auth`, unmounted `auth`) — drift risk; if re-mounted accidentally, inconsistent refresh/token logic and rate limits. Remove or consolidate unused router. (`backend/app/main.py`, `backend/app/routes/auth.py`, `backend/app/routes/api_auth.py`)
4. **`activities_read` uses `using (true)`** — any authenticated user can read all activities; verify feed content is safe or scope it. (`supabase/migrations/008_rls_app_policies.sql`)
5. **Service-role-only tables used in user flows** — e.g., `app.teacher_directory`, `app.teacher_approvals`, `app.meditations`, `app.tarot_requests` have no user policies. Confirm backend always uses privileged DB role; otherwise add user policies. (RLS matrix)
6. **JWT default secret (`change-me`)** — if env missing, tokens are trivially forgeable. Enforce env validation in runtime startup or fail fast. (`backend/app/config.py`, `ops/env_validate.sh`)
7. **Raw Request parsing in AI endpoints** — multiple AI endpoints parse request JSON manually; add explicit schemas and strict validation to reduce abuse surface. (`backend/app/routes/api_ai.py`)
8. **Multipart upload endpoints without explicit response models** — several upload/media endpoints return untyped responses; add schemas and server-side size/type constraints to reduce parsing ambiguity. (`backend/app/routes/api_auth.py`, `backend/app/routes/upload.py`, `backend/app/routes/studio.py`)
9. **Security definer functions (pgbouncer/vault)** — ensure grants are locked down; missing `grants.csv` snapshot prevents verification. Generate grants snapshot and audit. (`supabase/security_definer_export.sql`)
10. **OpenAPI coverage gaps** — endpoints without `response_model` or `include_in_schema=False` reduce contract visibility, which can hide security-sensitive changes. Add schemas or mark intentionally hidden with documentation. (`backend/app/routes/courses.py`, `API_CATALOG.md`)
