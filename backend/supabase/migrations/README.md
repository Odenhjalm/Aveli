## Legacy backend migration lineage

This directory is a non-authoritative historical reference surface.

- Canonical local verification DB authority is `backend/supabase/baseline_v2_slots/`.
- Locked canonical baseline scope is recorded in `backend/supabase/baseline_v2_slots.lock.json`.
- Production release migration tooling must not read from this directory.
- `backend/scripts/apply_supabase_migrations.sh` treats this directory as legacy-only and ignores it.

The files here may still encode retired membership, auth-subject, runtime-media, and profile-media doctrine.
Treat them as historical residue only. Do not use them to define canonical truth, local baseline replay, or production migration behavior.
