# V2 Cutover Plan

## Local v2 shadow test (copy/rename strategy)

Goal: replay the v2 chain from scratch without touching the existing migration history.

1) Create a temporary working copy (or git worktree) so you can safely swap folders.
2) Swap the migration directory to point at v2:

```bash
mv supabase/migrations supabase/migrations_v1
cp -R supabase/migrations_v2 supabase/migrations
```

3) Reset a local-only database (no remote writes):

```bash
supabase db reset --local
```

4) Restore the original migration folder after the test:

```bash
rm -rf supabase/migrations
mv supabase/migrations_v1 supabase/migrations
```

If you prefer not to rename folders in-place, do the same steps inside a worktree.

## Staging-first apply

1) Provision a fresh staging database or schema.
2) Apply the v2 chain in staging using the same copy/rename approach above.
3) Compare schema surfaces between the current drifted DB and v2 staging:

```bash
pg_dump --schema-only "$CURRENT_DB_URL" > /tmp/current_schema.sql
pg_dump --schema-only "$V2_STAGING_DB_URL" > /tmp/v2_schema.sql
```

4) Diff the dumps to identify gaps and verify RLS/policies.
5) Run smoke tests against staging to confirm core flows (auth, courses, orders, sessions, livekit, storage).

## Migrating from remote drift to the v2 baseline

1) Treat v2 as the schema baseline for new environments.
2) For existing data:
   - Export data from the current DB (read-only):
     ```bash
     pg_dump --data-only "$CURRENT_DB_URL" > /tmp/current_data.sql
     ```
   - Apply v2 migrations to a fresh staging DB.
   - Import the data dump into staging and resolve any conflicts.
3) Validate row counts and critical joins before considering cutover.
4) Only after staging parity is confirmed, plan a production cutover window.

## Freeze old chain

Keep `supabase/migrations/` unchanged for historical reference. The v2 chain lives exclusively in `supabase/migrations_v2/` and is the only path used for new replays.
