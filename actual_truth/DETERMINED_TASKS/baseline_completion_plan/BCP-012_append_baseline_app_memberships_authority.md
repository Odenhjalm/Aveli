# BCP-012

- TASK_ID: `BCP-012`
- TYPE: `OWNER`
- TITLE: `Append baseline ownership for canonical app.memberships`
- PROBLEM_STATEMENT: `Protected baseline slots 0001-0012 do not own app.memberships even though the locked direction makes app.memberships the canonical app-entry authority. The baseline must therefore gain append-only ownership above the lock boundary instead of mutating protected slots or relying on remote-schema drift.`
- IMPLEMENTATION_SURFACES:
  - `backend/supabase/baseline_slots/`
  - `backend/supabase/baseline_slots.lock.json`
  - `AVELI_DATABASE_BASELINE_MANIFEST.md`
- TARGET_STATE:
  - append-only slot(s) above `0012` baseline-own `app.memberships`
  - the baseline expression uses only the resolved minimum authority shape from `BCP-010`
  - the table keeps `user_id` as an external soft reference and does not add an `auth.users` foreign key
  - enrollment, onboarding, role, and admin fields are absent from `app.memberships`
  - protected slots remain unchanged
- DEPENDS_ON:
  - `BCP-011`
- VERIFICATION_METHOD:
  - refresh and verify `backend/supabase/baseline_slots.lock.json`
  - confirm new ownership exists only in append-only slots
  - confirm baseline shape does not reintroduce legacy subscription or duplicate app-entry semantics

## OWNER IMPLEMENTATION

- Appended `backend/supabase/baseline_slots/0013_memberships_core.sql` above the protected slot boundary.
- The new baseline-owned `app.memberships` shape contains only:
  - `membership_id`
  - `user_id`
  - `status`
  - `end_date`
  - `created_at`
  - `updated_at`
- The slot adds:
  - primary key on `membership_id`
  - unique constraint on `user_id`
- The `user_id` binding remains a soft external reference and does not add an `auth.users` foreign key.
- `AVELI_DATABASE_BASELINE_MANIFEST.md` now documents `memberships` as the sole canonical app-entry authority and explicitly excludes onboarding, role, admin, enrollment, Stripe, and legacy subscription drift from the baseline-owned shape.
- `backend/supabase/baseline_slots.lock.json` now includes slot `13` with the verified SHA-256 for `0013_memberships_core.sql`.

## OWNER EVIDENCE

- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-011_lock_app_entry_membership_boundary.md`
  - already passed the membership boundary gate and fixed `app.memberships` as the sole canonical app-entry owner.
- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-010_resolve_minimal_app_memberships_shape.md`
  - already locked the minimum canonical field set to `user_id`, `status`, `end_date` plus structural support fields `membership_id`, `created_at`, `updated_at`.
- `Aveli_System_Decisions.md`
  - fixes app-access authority as `memberships`
  - requires `user_id` to remain a soft reference for `auth.users(id)`
  - forbids database foreign keys for external dependencies
- `aveli_system_manifest.json`
  - fixes `app_access_authority = memberships`
  - fixes `membership_scope = global`
  - fixes `membership_required_for_app_entry = true`
- `backend/supabase/baseline_slots.lock.json`
  - protected slots stop at `0012`, so `app.memberships` ownership had to be appended above the lock boundary
- Deterministic inference used by this task:
  - one row per `user_id` is required to prevent duplicate app-entry semantics because the canonical source set fixes global membership scope and this task explicitly forbids duplicate app-entry authority

## OWNER VERIFICATION

- Parsed `backend/supabase/baseline_slots.lock.json` after mutation and confirmed:
  - `protected_max_slot = 12`
  - new slot = `13`
  - `0013_memberships_core.sql` hash matches the recorded SHA-256
- Verified `0013_memberships_core.sql` contains the required minimum canonical columns and constraints only.
- Verified `0013_memberships_core.sql` does not contain:
  - `foreign key`
  - `auth.users`
  - `plan_interval`
  - `price_id`
  - `stripe_customer_id`
  - `stripe_subscription_id`
  - `start_date`
  - onboarding, role, admin, enrollment, or unlock-state fields
- Verified protected slots `0001-0012` remain unchanged.

## EXECUTION LOCK

- EXPECTED_STATE:
  - baseline ownership for canonical `app.memberships` exists only in append-only slots above `0012`
  - the baseline-owned shape uses only the locked minimum authority contract
  - no external-auth foreign key or legacy billing authority is reintroduced
- ACTUAL_STATE:
  - baseline ownership now exists in `0013_memberships_core.sql`
  - manifest and lockfile are aligned to the new owner slot
  - the new slot keeps `user_id` soft, excludes legacy billing fields, and prevents duplicate app-entry rows per `user_id`
- REMAINING_RISKS:
  - mounted runtime code still expects Stripe-era membership fields and legacy helper paths until `BCP-013`
  - remote-schema drift still exists until baseline replay supersedes it
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `LOCKED_FOR_BCP-013`
