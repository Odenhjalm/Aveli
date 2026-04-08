# BCP-042

- TASK_ID: `BCP-042`
- TYPE: `OWNER`
- TITLE: `Append baseline ownership for unified runtime_media`
- PROBLEM_STATEMENT: `The protected baseline can no longer satisfy the locked media direction because slot 0008 is lesson-only and slot 0012 still exposes raw runtime_media access. Unified runtime truth must therefore be introduced append-only above the protected range.`
- IMPLEMENTATION_SURFACES:
  - `backend/supabase/baseline_slots/`
  - `backend/supabase/baseline_slots.lock.json`
  - `backend/supabase/baseline_slots/0008_runtime_media_projection_core.sql`
  - `backend/supabase/baseline_slots/0009_runtime_media_projection_sync.sql`
- TARGET_STATE:
  - append-only slot(s) above `0012` supersede the lesson-only `runtime_media` boundary
  - unified `runtime_media` carries the resolved runtime truth for visibility, state, and resolution eligibility
  - course cover participates in the same runtime chain as other governed surfaces
  - no direct application write path targets `runtime_media`
  - protected slots remain unchanged
- DEPENDS_ON:
  - `BCP-041`
- VERIFICATION_METHOD:
  - refresh and verify `backend/supabase/baseline_slots.lock.json`
  - confirm new runtime_media ownership exists only in append-only slots
  - confirm the baseline still treats Supabase Storage as substrate only

## OWNER IMPLEMENTATION

- Appended `backend/supabase/baseline_slots/0017_runtime_media_unified.sql` above the protected slot boundary.
- The new slot supersedes `app.runtime_media` with `create or replace view` rather than creating a second runtime-truth object.
- The superseding unified `app.runtime_media` now projects:
  - lesson-media rows from `app.lesson_media` -> `app.lessons` -> `app.media_assets`
  - course-cover rows from `app.courses.cover_media_id` -> `app.media_assets`
- The unified row shape now carries:
  - `lesson_media_id`
  - `lesson_id`
  - `course_id`
  - `media_asset_id`
  - `media_type`
  - `playback_object_path`
  - `playback_format`
  - `state`
- Course-cover rows are identified only by null `lesson_media_id` and null `lesson_id`.
- No direct write path to `app.runtime_media` was added.
- `backend/supabase/baseline_slots.lock.json` now includes slot `17` with the verified SHA-256 for `0017_runtime_media_unified.sql`.

## OWNER EVIDENCE

- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-041_lock_runtime_media_unification_boundary.md`
  - already passed the unified runtime-media gate and fixed one authority chain only
- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-040_resolve_unified_runtime_media_expansion.md`
  - already locked the in-scope row sources to lesson media and course cover only
  - already locked the required row fields and non-porting exclusions
  - already locked `app.runtime_media` itself as the canonical runtime-truth owner path
- `actual_truth/contracts/media_unified_authority_contract.md`
  - fixes one media authority chain only
  - forbids cover-specific authority and alternate runtime-media paths
- `actual_truth/contracts/COURSE_COVER_READ_CONTRACT.md`
  - keeps `app.courses.cover_media_id` pointer-only
  - requires cover to derive from canonical runtime truth in `app.runtime_media`
- `backend/supabase/baseline_slots/0008_runtime_media_projection_core.sql`
  - remained lesson-only and ready-only, so it could not satisfy the locked unified boundary
- `backend/supabase/baseline_slots/0009_runtime_media_projection_sync.sql`
  - already preserves projection-only doctrine with no sync or write path
- `backend/supabase/baseline_slots/0007_media_assets_core.sql`
  - already owns `media_type`, `state`, `playback_object_path`, and `playback_format`
  - already constrains purpose scope to `course_cover` and `lesson_media`
- Deterministic inference used by this task:
  - the canonical owner name had to remain `app.runtime_media`, so append-only supersedering required `create or replace view` instead of creating a parallel runtime object
  - `state` was appended to the protected view's existing column prefix to extend the row model without creating a second authority path

## OWNER VERIFICATION

- Parsed `backend/supabase/baseline_slots.lock.json` after mutation and confirmed:
  - `protected_max_slot = 12`
  - new slot = `17`
  - `0017_runtime_media_unified.sql` hash matches the recorded SHA-256
- Verified `0017_runtime_media_unified.sql` contains:
  - one `create or replace view app.runtime_media`
  - lesson-media rows keyed by `purpose = lesson_media`
  - course-cover rows keyed by `purpose = course_cover`
  - canonical `state` in the runtime projection
- Verified `0017_runtime_media_unified.sql` does not contain:
  - non-porting fields such as `reference_type`, `auth_scope`, `fallback_policy`, `home_player_upload_id`, `teacher_id`, `media_object_id`, legacy storage fields, or `kind`
  - direct writes to `app.runtime_media`
  - a ready-only filter on `ma.state`
- Verified protected slots `0001-0016` remain unchanged by this task.

## EXECUTION LOCK

- EXPECTED_STATE:
  - append-only baseline work supersedes the lesson-only `runtime_media` boundary above `0012`
  - unified `runtime_media` includes lesson media and course cover in one canonical runtime-truth chain
  - Supabase Storage remains substrate only and no direct application writes target `runtime_media`
- ACTUAL_STATE:
  - baseline ownership now exists in `0017_runtime_media_unified.sql`
  - `app.runtime_media` now carries both lesson-media and course-cover rows plus canonical `state`
  - no alternate runtime-media object or cover-specific truth path was introduced
- REMAINING_RISKS:
  - mounted backend read composition still assumes lesson-only runtime rows or separate cover resolution until `BCP-043`
  - protected raw grants on `app.runtime_media` remain substrate drift until later verification
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `LOCKED_FOR_BCP-043`
