## Legacy migration archives

`migrations_legacy_20260325/` and `migrations_legacy_20260326/` are historical archive trees.

- They are not the canonical local baseline.
- They are not the production release migration source.
- They preserve legacy remote-schema and transition-era doctrine for forensic reference only.

When canonical truth is needed, use:

- `backend/supabase/baseline_slots/`
- `backend/supabase/baseline_slots.lock.json`
- active contracts under `actual_truth/contracts/`

Do not treat archive migration presence as authority.
