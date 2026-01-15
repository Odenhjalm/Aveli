# V2 DB-First Plan

## Rationale
- The v1 chain has replay hazards (out-of-order RLS, late-created tables, and drift sync stubs).
- v2 is a clean, deterministic baseline built only from repo knowledge (legacy migrations + backend expectations).
- All objects are ordered so creates precede RLS/policies and function dependencies.

## Included in v2
- All tables, enums, views, and helper functions defined in `supabase/migrations/**`.
- Backend-missing objects now defined:
  - `app.subscriptions` (table)
  - `app.grade_quiz_and_issue_certificate` (function)
- Storage buckets required by the repo: `public-media`, `course-media`, `lesson-media`.

## Intentionally excluded
- Objects not defined in legacy migrations and not referenced by the backend:
  - `app.live_events`
  - `app.live_event_registrations`
- Any remote-only drift objects not present in the repo.

## Local-only validation (no remote)
Use a temporary swap of migrations so v2 replays from scratch locally:

```
mv supabase/migrations supabase/migrations_v1
cp -R supabase/migrations_v2 supabase/migrations
supabase db reset --local
rm -rf supabase/migrations
mv supabase/migrations_v1 supabase/migrations
```

Optional sanity checks:
```
psql "$DATABASE_URL" -c "select count(*) from app.profiles;"
psql "$DATABASE_URL" -c "select count(*) from app.courses;"
```

## Remote diff phase (manual, later)
- Freeze writes to staging.
- Dump the remote schema and compare to the v2 baseline (tables, enums, functions, views, RLS).
- Reconcile any drift by adding explicit migrations (do not edit the v2 baseline files).
- Run full staging replay and app smoke tests.
- Schedule production cutover with a backup and rollback plan.
