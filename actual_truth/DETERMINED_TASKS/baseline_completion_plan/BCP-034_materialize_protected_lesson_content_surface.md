# BCP-034

- TASK_ID: `BCP-034`
- TYPE: `OWNER`
- TITLE: `Materialize the protected user-scoped lesson-content DB surface`
- PROBLEM_STATEMENT: `Protected lesson reads still derive from raw-table semantics plus policies in the protected baseline. The locked direction requires one canonical protected DB surface for lesson content, user-scoped only by course enrollment and unlock position.`
- IMPLEMENTATION_SURFACES:
  - `backend/supabase/baseline_slots/`
  - `backend/supabase/baseline_slots.lock.json`
  - `backend/supabase/baseline_slots/0012_canonical_access_policies.sql`
- TARGET_STATE:
  - append-only slot(s) above `0012` materialize the protected lesson-content surface
  - the protected surface is user-scoped only through `course_enrollments` and `lesson.position <= current_unlock_position`
  - membership alone never grants protected lesson content
  - the protected surface exposes only lesson identity, structure, content, and lesson media
  - raw table grants are no longer the final protected read contract
- DEPENDS_ON:
  - `BCP-031`
- VERIFICATION_METHOD:
  - refresh and verify `backend/supabase/baseline_slots.lock.json`
  - confirm protected lesson-content access is append-only and explicit above the protected range
  - confirm no new entitlement shortcut or visibility shortcut is introduced

## OWNER IMPLEMENTATION

- Appended `backend/supabase/baseline_slots/0016_lesson_content_surface.sql` above the protected slot boundary.
- The new slot materializes `app.lesson_content_surface` as the canonical protected DB surface for learner lesson content.
- The new surface composes only:
  - `app.lessons`
  - `app.lesson_contents`
  - `app.lesson_media`
- The new surface scopes access only through:
  - `app.course_enrollments`
  - `lesson.position <= current_unlock_position`
- The new surface exposes only:
  - lesson identity and structure fields
  - `content_markdown`
  - lesson-media identity and placement fields
- The new surface is granted `select` to `public`.
- `backend/supabase/baseline_slots.lock.json` now includes slot `16` with the verified SHA-256 for `0016_lesson_content_surface.sql`.

## OWNER EVIDENCE

- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-031_lock_db_surface_contract_boundary.md`
  - already passed the protected-surface gate and fixed one canonical protected DB object path
- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-030_resolve_canonical_db_surface_map.md`
  - already locked `app.lesson_content_surface` as the only protected learner-content surface
  - already locked `app.lessons` + `app.lesson_contents` + `app.lesson_media` as the source boundary
  - already locked `course_enrollments` plus unlock position as the only access boundary
- `Aveli_System_Decisions.md`
  - fixes `lesson_content_surface` as accessible only when `course_enrollments` AND `lesson.position <= current_unlock_position`
  - forbids membership-only or visibility-only access interpretations
- `AVELI_DATABASE_BASELINE_MANIFEST.md`
  - fixes `lesson_content_surface` to `lessons` + `lesson_contents` + `lesson_media`
  - keeps `course_enrollments` as the only protected lesson-content authority
- `backend/supabase/baseline_slots/0012_canonical_access_policies.sql`
  - still expresses protected raw-table access through grants and policies, so append-only surface ownership was required above the protected range
- Deterministic inference used by this task:
  - `app.lesson_content_surface` is materialized as a flat relational projection because the canonical source set fixes one protected DB object and one allowed source boundary but does not authorize JSON/blob lesson-content surface contracts
  - the view intentionally carries the access predicate itself rather than inheriting final doctrine from protected raw-table policies

## OWNER VERIFICATION

- Parsed `backend/supabase/baseline_slots.lock.json` after mutation and confirmed:
  - `protected_max_slot = 12`
  - new slot = `16`
  - `0016_lesson_content_surface.sql` hash matches the recorded SHA-256
- Verified `0016_lesson_content_surface.sql` contains:
  - one named `app.lesson_content_surface` view
  - joins to `app.lesson_contents` and `app.lesson_media`
  - an explicit `exists` access predicate on `app.course_enrollments`
  - the `lesson.position <= current_unlock_position` boundary
- Verified `0016_lesson_content_surface.sql` does not contain:
  - `memberships`
  - `runtime_media`
  - `media_assets`
  - visibility shortcuts
  - resolved media representation fields
- Verified raw-table protected grants still exist only in protected slot `0012`, so the new view is an append-only contract addition rather than a protected-slot mutation.
- Verified protected slots `0001-0015` remain unchanged by this task.

## EXECUTION LOCK

- EXPECTED_STATE:
  - one append-only protected lesson-content surface exists above `0012`
  - the protected surface is scoped only by enrollment plus unlock position
  - membership or visibility alone never grant protected lesson content
- ACTUAL_STATE:
  - baseline ownership now exists in `0016_lesson_content_surface.sql`
  - the protected view enforces enrollment-plus-unlock access in the surface definition itself
  - the view exposes lesson identity, structure, content, and lesson-media fields only
- REMAINING_RISKS:
  - protected raw-table grants and policies still exist as substrate drift until later verification and consumer realignment
  - mounted runtime still consumes raw tables until `BCP-036`
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `LOCKED_FOR_BCP-035`
