# BCP-022

- TASK_ID: `BCP-022`
- TYPE: `OWNER`
- TITLE: `Append baseline ownership for the canonical auth-subject entity`
- PROBLEM_STATEMENT: `The protected baseline has no canonical auth-subject entity above Supabase Auth, so onboarding and role authority cannot become baseline-owned without append-only schema work. This must happen without mutating protected slots and without turning Supabase Auth into business-truth storage.`
- IMPLEMENTATION_SURFACES:
  - `backend/supabase/baseline_slots/`
  - `backend/supabase/baseline_slots.lock.json`
  - `AVELI_DATABASE_BASELINE_MANIFEST.md`
- TARGET_STATE:
  - append-only slot(s) above `0012` baseline-own the resolved canonical auth-subject entity
  - the baseline shape carries `onboarding_state`, `role_v2`, `role`, and `is_admin`
  - the baseline binds the entity to Supabase Auth through a soft external reference, not a database foreign key
  - `app.profiles` is not reused as the canonical owner for these authority fields
  - protected slots remain unchanged
- DEPENDS_ON:
  - `BCP-021`
- VERIFICATION_METHOD:
  - refresh and verify `backend/supabase/baseline_slots.lock.json`
  - confirm the baseline adds only append-only subject-entity ownership
  - confirm Supabase Auth remains substrate identity only

## OWNER IMPLEMENTATION

- Appended `backend/supabase/baseline_slots/0014_auth_subjects_core.sql` above the protected slot boundary.
- The new baseline-owned `app.auth_subjects` shape contains only:
  - `user_id`
  - `onboarding_state`
  - `role_v2`
  - `role`
  - `is_admin`
- The slot adds:
  - primary key on `user_id`
  - check constraints for canonical onboarding and role enums
- The `user_id` binding remains a soft external reference and does not add an `auth.users` foreign key.
- `AVELI_DATABASE_BASELINE_MANIFEST.md` now documents `auth_subjects` as the canonical subject-authority owner and explicitly excludes profile, membership, enrollment, and lesson-content access drift from the baseline-owned shape.
- `backend/supabase/baseline_slots.lock.json` now includes slot `14` with the verified SHA-256 for `0014_auth_subjects_core.sql`.

## OWNER EVIDENCE

- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-021_lock_auth_subject_separation_boundary.md`
  - already passed the auth-subject separation gate and fixed `app.auth_subjects` as the one subject-authority owner path
- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-020_resolve_canonical_auth_subject_entity.md`
  - already locked the entity name `app.auth_subjects`
  - already locked `user_id` as the only justified subject binding
  - already locked `onboarding_state`, `role_v2`, `role`, and `is_admin` as the only justified authority fields
- `actual_truth/contracts/onboarding_teacher_rights_contract.md`
  - defines the allowed values and required-state rules for `onboarding_state`, `role_v2`, `role`, and `is_admin`
  - preserves separation between canonical role truth, compatibility role fallback, and admin override
- `Aveli_System_Decisions.md`
  - keeps `auth.users` as an external dependency
  - forbids database foreign keys for external dependencies
  - keeps app-entry authority on `memberships` and learner-content authority on `course_enrollments`
- `backend/supabase/baseline_slots.lock.json`
  - protected slots stop at `0012`, so auth-subject ownership had to be appended above the lock boundary
- current remote-schema mismatch evidence only:
  - `app.profiles` mixes role/admin authority with presentation, billing-adjacent, and provider fields
  - therefore `app.profiles` cannot be reused as the canonical auth-subject owner
- Deterministic inferences used by this task:
  - `user_id` is the primary key because the resolved auth-subject entity has one canonical subject binding and no additional canonical identifier was justified
  - no `created_at` or `updated_at` fields were added because `BCP-020` locked only the binding field plus the four authority fields as the minimum canonical shape

## OWNER VERIFICATION

- Parsed `backend/supabase/baseline_slots.lock.json` after mutation and confirmed:
  - `protected_max_slot = 12`
  - new slot = `14`
  - `0014_auth_subjects_core.sql` hash matches the recorded SHA-256
- Verified `0014_auth_subjects_core.sql` contains the required minimum canonical columns and constraints only.
- Verified `0014_auth_subjects_core.sql` does not contain:
  - `foreign key`
  - `auth.users`
  - defaults
  - profile presentation fields
  - provider or billing fields
  - membership, enrollment, or unlock-state fields
  - `created_at` or `updated_at`
- Verified protected slots `0001-0013` remain unchanged by this task.

## EXECUTION LOCK

- EXPECTED_STATE:
  - baseline ownership for the canonical auth-subject entity exists only in append-only slots above `0012`
  - the baseline-owned shape carries only the locked subject binding and four authority fields
  - Supabase Auth remains substrate identity only through a soft external reference
- ACTUAL_STATE:
  - baseline ownership now exists in `0014_auth_subjects_core.sql`
  - manifest and lockfile are aligned to the new owner slot
  - the new slot enforces the canonical field enum boundaries without reusing `app.profiles` or adding an external-auth foreign key
- REMAINING_RISKS:
  - mounted runtime still reads and writes auth-subject authority through `app.profiles` and JWT fallback until `BCP-023`
  - remote-schema profile drift still exists until baseline replay and runtime alignment supersede it
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `LOCKED_FOR_BCP-023`
