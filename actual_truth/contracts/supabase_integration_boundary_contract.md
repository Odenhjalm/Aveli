# SUPABASE INTEGRATION BOUNDARY CONTRACT

## STATUS

ACTIVE

This contract defines the canonical integration boundary between Aveli and Supabase.
It operates under `SYSTEM_LAWS.md`, `auth_onboarding_contract.md`,
`profile_projection_contract.md`, and `media_pipeline_contract.md`.

## 1. INFRASTRUCTURE RESPONSIBILITY MAP

- `auth.users` is identity-only.
  - Allowed responsibility:
    - user id
    - canonical email identity
    - credential/authentication substrate
    - auth token verification substrate
  - Forbidden responsibility:
    - onboarding state
    - role truth
    - application access truth
    - profile/media runtime truth
    - frontend representation truth

- `storage.objects` and `storage.buckets` are physical file persistence only.
  - Allowed responsibility:
    - bucket/object persistence
    - object existence
    - file metadata needed to read/write bytes
  - Forbidden responsibility:
    - media intent
    - media runtime truth
    - access decisions
    - frontend delivery authority

- Supabase-hosted Postgres is physical storage only.
  - Allowed responsibility:
    - persistence of canonical backend-owned tables and views
    - baseline-backed relational shape
  - Forbidden responsibility:
    - defining domain behavior through non-baseline schema drift
    - redefining canonical authorities through legacy columns or legacy migrations

## 2. BACKEND-OWNED DOMAIN AUTHORITIES

- `app.auth_subjects` is the canonical application subject authority for:
  - onboarding subject state
  - app-level role subject fields
- `app.profiles` is projection-only and non-authoritative.
- `app.memberships` owns app-access truth.
- `app.course_enrollments` owns protected course-content access truth.
- `app.media_assets` owns canonical media-asset lifecycle truth.
- Backend read composition owns frontend-facing media/profile representation.

## 3. MEDIATION LAW

- All Supabase interactions must be mediated through backend code.
- Frontend must use backend APIs only.
- Frontend must not instantiate Supabase auth, database, or storage clients for runtime behavior.
- Backend may call Supabase infrastructure only to:
  - verify auth tokens
  - create/update/read identity rows in `auth.users`
  - sign/read/write/delete storage objects
  - persist/read canonical backend-owned tables

## 4. BASELINE LAW

- Canonical schema authority is `backend/supabase/baseline_v2_slots`.
- No backend or frontend runtime behavior may depend on Supabase schema outside baseline.
- Legacy migration artifacts may exist for reference, but they are never runtime authority.
- External Supabase dependencies remain soft references only and must not become database-owned domain truth.

## 5. FORBIDDEN PATTERNS

- Reading onboarding, role, admin, membership, or media runtime truth from `auth.users`.
- Using Supabase auth metadata as profile or media fallback truth.
- Using `storage.objects` or storage URLs as media/runtime/domain authority.
- Letting frontend construct Supabase storage or auth logic as canonical behavior.
- Adapting runtime behavior to legacy/non-baseline schema columns.
- Treating Supabase-managed legacy migrations as runtime authority.

## 6. VERIFICATION TARGET

The boundary is correct only when all are true:

- `auth.users` is used only for identity/auth substrate.
- storage is used only for files/persistence.
- database behavior is baseline-backed and backend-owned.
- onboarding, roles, access, and runtime media truth remain backend authorities.
- frontend depends on backend APIs, not Supabase logic.
